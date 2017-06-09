package vshaxe;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import Vscode.*;
import vscode.*;
import js.Promise;
import js.node.ChildProcess;
import js.node.Buffer;
using StringTools;
using Lambda;

class HaxelibExplorer {
    var context:ExtensionContext;
    var configuration:Array<String>;
    var haxelibs:Array<Node>;
    var haxelibRepo(get,never):String;

    function get_haxelibRepo():String {
        if (_haxelibRepo == null) {
            _haxelibRepo = Path.normalize((ChildProcess.execSync('haxelib config') : Buffer).toString().trim());
        }
        return _haxelibRepo;
    }

    var _onDidChangeTreeData = new EventEmitter<Node>();
    var _haxelibRepo:String;

    public var onDidChangeTreeData:Event<Node>;

    public function new(context:ExtensionContext, configuration:Array<String>) {
        this.context = context;
        this.configuration = configuration;

        onDidChangeTreeData = _onDidChangeTreeData.event;
        window.registerTreeDataProvider("haxelibDependencies", this);
        commands.registerCommand("haxe.openHaxelibFile", openFile);
    }

    function updateHaxelibs(configuration:Array<String>) {
        haxelibs = [];

        // TODO: register a file watcher for hxml files / listen to setting.json changes
        var hxmlFile = workspace.rootPath + "/" + configuration[0]; // TODO: this isn't a safe assumption
        if (hxmlFile != null && FileSystem.exists(hxmlFile)) {
            var hxml = File.getContent(hxmlFile);
            // TODO: parse the hxml properly
            ~/-lib\s+([\w:.]+)/g.map(hxml, function(ereg) {
                var name = ereg.matched(1);
                var path = getHaxelibPath(name);
                if (path != null) {
                    addHaxelib(path);
                }
                return "";
            });

            ~/-cp\s+(.*)/g.map(hxml, function(ereg) {
                addHaxelib(ereg.matched(1));
                return "";
            });
        }
    }

    function addHaxelib(path:String) {
        // don't add duplicates
        if (haxelibs.find(haxelib -> haxelib.path == path) != null) {
            return;
        }
        var info = getHaxelibInfo(path);
        if (info == null) {
            return;
        }
        var label = '${info.name} (${info.version})';
        haxelibs.push(new Node(label, info.path));
    }

    function getHaxelibPath(lib:String):String {
        try {
            var result:Buffer = ChildProcess.execSync('haxelib path $lib');
            var path = null;
            for (line in result.toString().split("\n")) {
                var potentialPath = Path.normalize(line.trim());
                if (FileSystem.exists(potentialPath)) {
                    if (path == null) { // first path == path of the lib itself
                        path = potentialPath;
                    } else { // path of a depdendency
                        addHaxelib(potentialPath);
                    }
                }
            }
            return path;
        } catch(e:Any) {
            return null;
        }
    }

    function getHaxelibInfo(path:String) {
        if (path.indexOf(haxelibRepo) == -1) {
            // TODO: deal with paths outside of haxelib
            return null;
        }

        path = path.replace(haxelibRepo, "");
        var segments = path.split("/");
        var name = segments[1];
        var version = segments[2];
        var path = '$haxelibRepo/$name/$version';
        return {name:name, version:version.replace(",", "."), path:path};
    }

    public function onDisplayConfigurationChanged(configuration:Array<String>) {
        this.configuration = configuration;
        haxelibs = null;
        _onDidChangeTreeData.fire();
    }

    public function getTreeItem(element:Node):TreeItem {
        return element;
    }

    public function getChildren(?node:Node):Thenable<Array<Node>> {
        return new Promise(function(resolve, _) {
            if (haxelibs == null) {
                updateHaxelibs(configuration);
            }

            if (node == null) {
                resolve(haxelibs);
            } else {
                resolve(getNodeChildren(node));
            }
        });
    }

    function getNodeChildren(node:Node):Array<Node> {
        if (!node.isDirectory) {
            return [];
        }
        return [for (file in FileSystem.readDirectory(node.path)) {
            new Node(file, '${node.path}/$file');
        }];
    }

    function openFile(node:Node) {
        workspace.openTextDocument(node.path).then(document -> window.showTextDocument(document, {preview: true}));
    }
}

private class Node extends TreeItem {
    public var path(default,null):String;
    public var isDirectory(default,null):Bool;

    public function new(label:String, path:String) {
        super(label);
        this.path = path;
        isDirectory = FileSystem.isDirectory(path);
        if (isDirectory) {
            collapsibleState = Collapsed;
        } else {
            command = {
                command: "haxe.openHaxelibFile",
                arguments: [this],
                title: "Open File"
            };
        }
    }
}