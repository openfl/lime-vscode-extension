package vshaxe.projectTypes;

import js.node.Buffer;
import js.node.ChildProcess;
import vscode.ExtensionContext;
import vscode.QuickPickItem;
import vscode.StatusBarItem;
import Vscode.*;
using vshaxe.helper.ArrayHelper;

class LimeProjectType extends AbstractProjectType {
    var selectTargetItem:StatusBarItem;
    var selectBuildConfigItem:StatusBarItem;
    var editTargetFlagsItem:StatusBarItem;
    var targetItems:Array<TargetItem>;
    var buildConfigItems:Array<BuildConfigItem>;
    var lastLanguage:String;
    var displayArguments:Array<String> = [];

    public function new(context:ExtensionContext) {
        super(context, "lime");

        selectTargetItem = window.createStatusBarItem(Left, 19);
        selectTargetItem.tooltip = "Select Target";
        selectTargetItem.command = "haxe.lime.selectTarget";
        context.subscriptions.push(selectTargetItem);

        selectBuildConfigItem = window.createStatusBarItem(Left, 18);
        selectBuildConfigItem.tooltip = "Select Build Configuration";
        selectBuildConfigItem.command = "haxe.lime.selectBuildConfig";
        context.subscriptions.push(selectBuildConfigItem);

        editTargetFlagsItem = window.createStatusBarItem(Left, 17);
        editTargetFlagsItem.tooltip = "Additional Command-Line Arguments";
        editTargetFlagsItem.command = "haxe.lime.editTargetFlags";
        context.subscriptions.push(editTargetFlagsItem);

        targetItems = [
            {
                target: "windows",
                label: "Windows",
                description: "",
            },
            {
                target: "mac",
                label: "macOS",
                description: "",
            },
            {
                target: "linux",
                label: "Linux",
                description: "",
            },
            {
                target: "ios",
                label: "iOS",
                description: "",
            },
            {
                target: "android",
                label: "Android",
                description: "",
            },
            {
                target: "flash",
                label: "Flash",
                description: "",
            },
            {
                target: "html5",
                label: "HTML5",
                description: "",
            },
            {
                target: "emscripten",
                label: "Emscripten",
                description: "",
            }
        ];

        buildConfigItems = [
            {
                flags: "-debug",
                label: "Debug",
                description: "",
            },
            {
                flags: "",
                label: "Release",
                description: "",
            },
            {
                flags: "-final",
                label: "Final",
                description: "",
            }
        ];

        context.subscriptions.push(commands.registerCommand("haxe.lime.selectTarget", selectTarget));
        context.subscriptions.push(commands.registerCommand("haxe.lime.selectBuildConfig", selectBuildConfig));
        context.subscriptions.push(commands.registerCommand("haxe.lime.editTargetFlags", editTargetFlags));


        context.subscriptions.push(workspace.onDidChangeConfiguration(onDidChangeConfiguration));
        context.subscriptions.push(window.onDidChangeActiveTextEditor(onDidChangeActiveTextEditor));
    }

    public override function disable() {
        enabled = false;
        updateStatusBarItems();
    }

    public override function enable() {
        enabled = true;

        // fixIndex();
        updateStatusBarItems();
        // configuration = getConfiguration();
    }

    function fixIndex() {
        // var index = getIndex();
        // var configs = getConfigurations();
        // if (configs == null || index >= configs.length)
        //     setIndex(0);
    }

    function selectTarget() {
        if (!enabled) return;
        // var configs = getConfigurations();
        // if (configs == null || configs.length == 0) {
        //     window.showErrorMessage("No Haxe display configurations are available. Please provide the haxe.displayConfigurations setting.", ({title: "Edit settings"} : vscode.MessageItem)).then(function(button) {
        //         if (button == null)
        //             return;
        //         workspace.openTextDocument(workspace.rootPath + "/.vscode/settings.json").then(function(doc) window.showTextDocument(doc));
        //     });
        //     return;
        // }
        // if (configs.length == 1) {
        //     window.showInformationMessage("Only one Haxe display configuration found: " + configs[0].join(" "));
        //     return;
        // }

        var items = targetItems;

        window.showQuickPick(items, {matchOnDescription: true, placeHolder: "Select Target"}).then(function(choice:TargetItem) {
            if (choice == null || choice.target == getTarget())
                return;
            setTarget(choice.target);
        });
    }

    function selectBuildConfig() {
        if (!enabled) return;
        // var configs = getConfigurations();
        // if (configs == null || configs.length == 0) {
        //     window.showErrorMessage("No Haxe display configurations are available. Please provide the haxe.displayConfigurations setting.", ({title: "Edit settings"} : vscode.MessageItem)).then(function(button) {
        //         if (button == null)
        //             return;
        //         workspace.openTextDocument(workspace.rootPath + "/.vscode/settings.json").then(function(doc) window.showTextDocument(doc));
        //     });
        //     return;
        // }
        // if (configs.length == 1) {
        //     window.showInformationMessage("Only one Haxe display configuration found: " + configs[0].join(" "));
        //     return;
        // }

        var items = buildConfigItems;

        window.showQuickPick(items, {matchOnDescription: true, placeHolder: "Select Build Configuration"}).then(function(choice:BuildConfigItem) {
            // TODO: Read target flags, catch automatically
            if (choice == null || choice.flags == getBuildConfigFlags())
                return;
            setBuildConfigFlags(choice.flags);
        });
    }

    function editTargetFlags() {
        if (!enabled) return;
        var flags = getTargetFlags();
        window.showInputBox({ prompt: "Additional Command-Line Arguments", value: flags + " ", valueSelection: [ flags.length + 1, flags.length + 1 ] }).then(function(value:String) {
            setTargetFlags(StringTools.trim(value));
        });
    }

    function onDidChangeConfiguration(_) {
        fixIndex();
        updateStatusBarItems();
        checkConfigurationChange();
    }

    function onDidChangeActiveTextEditor(_) {
        updateStatusBarItems();
    }

    function updateDisplayArguments() {
        var buildConfigFlags = getBuildConfigFlags();
        var targetFlags = getTargetFlags();
        var commandLine = StringTools.trim("lime display " + getTarget() + (buildConfigFlags != "" ? " " + buildConfigFlags : "") + (targetFlags != "" ? " " + targetFlags : ""));
        trace ("Running display command: " + commandLine);
        try {
            var result:Buffer = ChildProcess.execSync(commandLine, { cwd: workspace.rootPath });
            var args = result.toString().split("\n");
            trace (args);
            displayArguments = args;
        } catch (e:Dynamic) {
            trace ("Error running display command: " + commandLine);
            trace (e);
        }
        onDidChangeDisplayArguments(displayArguments);
    }

    function updateStatusBarItems() {
        //var hasEditor = (window.activeTextEditor != null);
        //var isDocument = hasEditor && languages.match({language: 'haxe', scheme: 'file'}, window.activeTextEditor.document) > 0;
        //var isRelatedPanel = hasEditor && (window.activeTextEditor.document:Dynamic).scheme != "file" && lastLanguage == "haxe";

        if (enabled /*&& (isDocument || isRelatedPanel)*/) {
            var target = getTarget();
            for (i in 0...targetItems.length) {
                var item = targetItems[i];
                if (item.target == target) {
                    selectTargetItem.text = item.label;
                    selectTargetItem.show();
                    break;
                }
            }

            var buildConfigFlags = getBuildConfigFlags();
            for (i in 0...buildConfigItems.length) {
                var item = buildConfigItems[i];
                if (item.flags == buildConfigFlags) {
                    selectBuildConfigItem.text = item.label;
                    selectBuildConfigItem.show();
                    break;
                }
            }

            editTargetFlagsItem.text = "$(list-unordered)";
            editTargetFlagsItem.show();
            lastLanguage = "haxe";
            return;
        }

        lastLanguage = null;
        selectTargetItem.hide();
        selectBuildConfigItem.hide();
        editTargetFlagsItem.hide();
    }

    inline function getConfigurations():Array<Array<String>> {
        return workspace.getConfiguration("haxe").get("displayConfigurations");
    }

    public override function getDisplayArguments():Array<String> {
        if (displayArguments.length == 0) {
            updateDisplayArguments();
        }
        return displayArguments;
    }

    public function getTarget():String {
        return context.workspaceState.get("haxe.lime.target", "html5");
    }

    function setTarget(target:String) {
        context.workspaceState.update("haxe.lime.target", target);
        updateStatusBarItems();
        updateDisplayArguments();
        //onDidChangeIndex(index);
        //checkConfigurationChange();
    }

    public function getBuildConfigFlags():String {
        return context.workspaceState.get("haxe.lime.buildConfigFlags", "");
    }

    function setBuildConfigFlags(flags:String) {
        context.workspaceState.update("haxe.lime.buildConfigFlags", flags);
        updateStatusBarItems();
        updateDisplayArguments();
        //onDidChangeIndex(index);
        //checkConfigurationChange();
    }

    public function getTargetFlags():String {
        return context.workspaceState.get("haxe.lime.additionalTargetFlags", "");
    }

    function setTargetFlags(flags:String) {
        context.workspaceState.update("haxe.lime.additionalTargetFlags", flags);
        updateDisplayArguments();
        //updateStatusBarItems();
        //onDidChangeIndex(index);
        //checkConfigurationChange();
    }

    function checkConfigurationChange() {
        // var newConfiguration = getConfiguration();
        // if (!newConfiguration.equals(configuration)) {
        //     onDidChangeDisplayConfiguration(newConfiguration);
        //     configuration = newConfiguration;
        // }
    }

    //public dynamic function onDidChangeIndex(index:Int):Void {}

    //public dynamic function onDidChangeDisplayConfiguration(configuration:Array<String>):Void {}
}

private typedef TargetItem = {
    >QuickPickItem,
    var target:String;
}

private typedef BuildConfigItem = {
    >QuickPickItem,
    var flags:String;
}