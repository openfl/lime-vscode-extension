package vshaxe.projectTypes;

import Vscode.*;
import vscode.*;

class AbstractProjectType {
    public var id(default, null):String;
    var context:ExtensionContext;
    var enabled:Bool;

    private function new (context:ExtensionContext, id:String) {
        this.context = context;
        this.id = id;
    }

    public function getDisplayArguments():Array<String> {
        return [];
    }

    public function getIndex():Int {
        return 0;
    }

    public function disable():Void {
        enabled = false;
    }

    public function enable():Void {
        enabled = true;
    }

    public dynamic function onDidChangeDisplayArguments(args:Array<String>):Void {}
}