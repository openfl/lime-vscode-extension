package vshaxe.projectTypes;

import vscode.ExtensionContext;
import vscode.QuickPickItem;
import vscode.StatusBarItem;
import Vscode.*;
using vshaxe.helper.ArrayHelper;

class HXMLProjectType extends AbstractProjectType {
    var statusBarItem:StatusBarItem;
    var configuration:Array<String>;

    public function new(context:ExtensionContext) {
        super(context, "hxml");

        statusBarItem = window.createStatusBarItem(Left);
        statusBarItem.tooltip = "Select HXML Configuration";
        statusBarItem.command = "haxe.hxml.selectDisplayConfiguration";
        context.subscriptions.push(statusBarItem);

        context.subscriptions.push(commands.registerCommand("haxe.hxml.selectDisplayConfiguration", selectConfiguration));

        context.subscriptions.push(workspace.onDidChangeConfiguration(onDidChangeConfiguration));
        context.subscriptions.push(window.onDidChangeActiveTextEditor(onDidChangeActiveTextEditor));
    }

    public override function disable() {
        enabled = false;
        updateStatusBarItem();
    }

    public override function enable() {
        enabled = true;

        fixIndex();
        updateStatusBarItem();
        configuration = getDisplayArguments();
    }

    function fixIndex() {
        var index = getIndex();
        var configs = getConfigurations();
        if (configs == null || index >= configs.length)
            setIndex(0);
    }

    function selectConfiguration() {
        if (!enabled) return;
        var configs = getConfigurations();
        if (configs == null || configs.length == 0) {
            window.showErrorMessage("No Haxe display configurations are available. Please provide the haxe.displayConfigurations setting.", ({title: "Edit settings"} : vscode.MessageItem)).then(function(button) {
                if (button == null)
                    return;
                workspace.openTextDocument(workspace.rootPath + "/.vscode/settings.json").then(function(doc) window.showTextDocument(doc));
            });
            return;
        }
        if (configs.length == 1) {
            window.showInformationMessage("Only one Haxe display configuration found: " + configs[0].join(" "));
            return;
        }

        var items:Array<DisplayConfigurationPickItem> = [];
        for (index in 0...configs.length) {
            var args = configs[index];
            var label = args.join(" ");
            items.push({
                label: "" + index,
                description: label,
                index: index,
            });
        }

        window.showQuickPick(items, {matchOnDescription: true, placeHolder: "Select HXML Configuration"}).then(function(choice:DisplayConfigurationPickItem) {
            if (choice == null || choice.index == getIndex())
                return;
            setIndex(choice.index);
        });
    }

    function onDidChangeConfiguration(_) {
        fixIndex();
        updateStatusBarItem();
        checkConfigurationChange();
    }

    function onDidChangeActiveTextEditor(_) {
        updateStatusBarItem();
    }

    function updateStatusBarItem() {
        if (!enabled || window.activeTextEditor == null) {
            statusBarItem.hide();
            return;
        }

        if (languages.match({language: 'haxe', scheme: 'file'}, window.activeTextEditor.document) > 0) {
            var configs = getConfigurations();
            if (configs != null && configs.length >= 2) {
                var index = getIndex();
                statusBarItem.text = '$(gear) Haxe: $index (${configs[index].join(" ")})';
                statusBarItem.show();
                return;
            }
        }

        statusBarItem.hide();
    }

    inline function getConfigurations():Array<Array<String>> {
        return workspace.getConfiguration("haxe").get("displayConfigurations");
    }

    public override function getDisplayArguments():Array<String> {
        return getConfigurations()[getIndex()];
    }

    public override function getIndex():Int {
        return context.workspaceState.get("haxe.hxml.displayConfigurationIndex", 0);
    }

    function setIndex(index:Int) {
        context.workspaceState.update("haxe.hxml.displayConfigurationIndex", index);
        updateStatusBarItem();
        //onDidChangeIndex(index);
        checkConfigurationChange();
    }

    function checkConfigurationChange() {
        var newConfiguration = getDisplayArguments();
        if (!newConfiguration.equals(configuration)) {
            //onDidChangeDisplayConfiguration(newConfiguration);
            configuration = newConfiguration;
        }
    }

    //public dynamic function onDidChangeIndex(index:Int):Void {}

    //public dynamic function onDidChangeDisplayConfiguration(configuration:Array<String>):Void {}
}

private typedef DisplayConfigurationPickItem = {
    >QuickPickItem,
    var index:Int;
}