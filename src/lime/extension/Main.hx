package lime.extension;

import js.node.Buffer;
import js.node.ChildProcess;
import sys.FileSystem;
import haxe.io.Path;
import haxe.DynamicAccess;
import Vscode.*;
import vscode.*;

using lime.extension.ArrayHelper;
using Lambda;

class Main
{
	private static var instance:Main;

	private var context:ExtensionContext;
	private var displayArgumentsProvider:DisplayArgsProvider;
	private var disposables:Array<{function dispose():Void;}>;
	private var hasProjectFile:Bool;
	private var initialized:Bool;
	private var isProviderActive:Bool;
	private var selectTargetItem:StatusBarItem;
	private var targetItems:Array<TargetItem>;
	private var haxeEnvironment:DynamicAccess<String>;
	private var limeCommands:Array<LimeCommand>;
	private var limeExecutable:String;
	private var limeTargets:Map<String, String>;
	private var limeVerbose:Bool;
	private var limeVersion:SemVer = "0.0.0";
	private var toggleVerboseItem:StatusBarItem;

	public function new(context:ExtensionContext)
	{
		this.context = context;

		registerDebugConfigurationProviders();

		context.subscriptions.push(workspace.onDidChangeConfiguration(workspace_onDidChangeConfiguration));
		refresh();
	}

	private function checkHasProjectFile():Void
	{
		hasProjectFile = false;

		if (getProjectFile() != "")
		{
			hasProjectFile = true;
		}

		if (!hasProjectFile)
		{
			// TODO: multi-folder support

			var wsFolder = if (workspace.workspaceFolders == null) null else workspace.workspaceFolders[0];
			var rootPath = wsFolder.uri.fsPath;

			if (rootPath != null)
			{
				// TODO: support custom project file references

				var files = ["project.xml", "Project.xml", "project.hxp", "project.lime"];

				for (file in files)
				{
					if (FileSystem.exists(rootPath + "/" + file))
					{
						hasProjectFile = true;
						break;
					}
				}
			}
		}
	}

	private function construct():Void
	{
		disposables = [];

		selectTargetItem = window.createStatusBarItem(Left, 9);
		selectTargetItem.tooltip = "Select Lime Target Configuration";
		selectTargetItem.command = "lime.selectTarget";
		disposables.push(selectTargetItem);

		toggleVerboseItem = window.createStatusBarItem(Left, 8);
		toggleVerboseItem.command = "lime.toggleVerbose";
		disposables.push(toggleVerboseItem);

		disposables.push(commands.registerCommand("lime.selectTarget", selectTargetItem_onCommand));
		disposables.push(commands.registerCommand("lime.toggleVerbose", toggleVerboseItem_onCommand));
		disposables.push(tasks.registerTaskProvider("lime", this));
	}

	private function deconstruct():Void
	{
		if (disposables == null)
		{
			return;
		}

		for (disposable in disposables)
		{
			disposable.dispose();
		}

		selectTargetItem = null;
		toggleVerboseItem = null;

		disposables = null;
		initialized = false;
	}

	private function constructDisplayArgumentsProvider()
	{
		var api:Vshaxe = getVshaxe();

		displayArgumentsProvider = new DisplayArgsProvider(api, function(isProviderActive)
		{
			this.isProviderActive = isProviderActive;
			refresh();
		});

		if (untyped !api)
		{
			trace("Warning: Haxe language server not available (using an incompatible vshaxe version)");
		}
		else
		{
			api.registerDisplayArgumentsProvider("Lime", displayArgumentsProvider);
		}
	}

	private function createTask(command:String, additionalArgs:Array<String>, presentation:vshaxe.TaskPresentationOptions, problemMatchers:Array<String>,
			group:TaskGroup = null)
	{
		command = StringTools.trim(command);

		var definition:LimeTaskDefinition =
			{
				type: "lime",
				command: command
			}

		var shellCommand = limeExecutable + " " + command;
		if (additionalArgs != null) shellCommand += " " + additionalArgs.join(" ");

		var task = new Task(definition, TaskScope.Workspace, command, "lime");
		task.execution = new ShellExecution(shellCommand,
			{
				cwd: workspace.workspaceFolders[0].uri.fsPath,
				env: haxeEnvironment
			});

		if (group != null)
		{
			task.group = group;
		}

		task.problemMatchers = problemMatchers;
		task.presentationOptions =
			{
				reveal: presentation.reveal,
				echo: presentation.echo,
				focus: presentation.focus,
				panel: presentation.panel,
				showReuseMessage: presentation.showReuseMessage,
				clear: presentation.clear
			};

		return task;
	}

	private function getCommandArguments(command:String, targetItem:TargetItem):String
	{
		var target = targetItem.target;
		var args = (targetItem.args != null ? targetItem.args.copy() : []);

		var projectFile = getProjectFile();
		if (projectFile != "")
		{
			args.unshift(projectFile);
		}

		// TODO: Should this be separate?

		if (args.indexOf("-debug") > -1)
		{
			switch (target)
			{
				case "windows", "mac", "linux":
					if (hasExtension("vshaxe.hxcpp-debugger"))
					{
						args.push("--haxelib=hxcpp-debug-server");
					}

				case "flash":
					args.push("-Dfdb");

				default:
			}
		}

		return command + " " + target + " " + args.join(" ");
	}

	private function getExecutable():String
	{
		var executable = workspace.getConfiguration("lime").get("executable");
		if (executable == null)
		{
			executable = "lime";
		}
		// naive check to see if it's a path, or multiple arguments such as "haxelib run lime"
		if (FileSystem.exists(executable))
		{
			executable = '"' + executable + '"';
		}
		return executable;
	}

	private function getLimeVersion():Void
	{
		try
		{
			var output = ChildProcess.execSync(limeExecutable + " -version", {cwd: workspace.workspaceFolders[0].uri.fsPath});
			limeVersion = StringTools.trim(Std.string(output));
		}
		catch (e:Dynamic)
		{
			limeVersion = "0.0.0";
			trace(e);
		}
	}

	public function getProjectFile():String
	{
		var config = workspace.getConfiguration("lime");

		if (config.has("projectFile"))
		{
			var projectFile = Std.string(config.get("projectFile"));
			if (projectFile == "null") projectFile = "";
			return projectFile;
		}
		else
		{
			return "";
		}
	}

	public function getTargetItem():TargetItem
	{
		var defaultTargetConfig = workspace.getConfiguration("lime").get("defaultTargetConfiguration", "HTML5");
		var defaultTargetItem = targetItems.find(function(item)
		{
			return item.label == defaultTargetConfig;
		});

		if (defaultTargetItem != null)
		{
			defaultTargetConfig = defaultTargetItem.label;
		}

		var targetConfig = context.workspaceState.get("lime.targetConfiguration", defaultTargetConfig);
		var targetItem = targetItems.find(function(item)
		{
			return item.label == targetConfig;
		});

		if (targetItem == null)
		{
			targetItem = defaultTargetItem;
		}

		if (targetItem == null)
		{
			targetItem = targetItems[0];
		}

		return targetItem;
	}

	private inline function getVshaxe():Vshaxe
	{
		return extensions.getExtension("nadako.vshaxe").exports;
	}

	private function hasExtension(id:String, shouldInstall:Bool = false, message:String = ""):Bool
	{
		if (extensions.getExtension(id) == js.Lib.undefined)
		{
			if (shouldInstall)
			{
				// TODO: workbench.extensions.installExtension not available?
				// var installNowLabel = "Install Now";
				// window.showErrorMessage(message, installNowLabel).then(function(selection)
				// {
				// 	trace(selection);
				// 	if (selection == installNowLabel)
				// 	{
				// 		commands.executeCommand("workbench.extensions.installExtension", id);
				// 	}
				// });
				window.showWarningMessage(message);
			}
			return false;
		}
		else
		{
			return true;
		}
	}

	private function initialize():Void
	{
		getLimeVersion();

		// TODO: Detect automatically?

		limeCommands = [CLEAN, UPDATE, BUILD, RUN, TEST];

		updateTargetItems();

		getVshaxe().haxeExecutable.onDidChangeConfiguration(function(_) updateHaxeEnvironment());
		updateHaxeEnvironment();

		initialized = true;
	}

	private function updateHaxeEnvironment()
	{
		var haxeConfiguration = getVshaxe().haxeExecutable.configuration;
		var env = new DynamicAccess();

		for (field in Reflect.fields(haxeConfiguration.env))
		{
			env[field] = haxeConfiguration.env[field];
		}

		if (!haxeConfiguration.isCommand)
		{
			var separator = Sys.systemName() == "Windows" ? ";" : ":";
			env["PATH"] = Path.directory(haxeConfiguration.executable) + separator + Sys.getEnv("PATH");
		}

		haxeEnvironment = env;
	}

	@:keep @:expose("activate") public static function activate(context:ExtensionContext)
	{
		instance = new Main(context);
	}

	@:keep @:expose("deactivate") public static function deactivate()
	{
		instance.deconstruct();
	}

	static function main() {}

	public function provideDebugConfigurations(folder:Null<WorkspaceFolder>, ?token:CancellationToken):ProviderResult<Array<DebugConfiguration>>
	{
		return [
			{
				"name": "Lime",
				"type": "lime",
				"request": "launch"
			}];
	}

	public function provideTasks(?token:CancellationToken):ProviderResult<Array<Task>>
	{
		var targetItem = getTargetItem();
		var vshaxe = getVshaxe();
		var displayPort = vshaxe.displayPort;
		var problemMatchers = vshaxe.problemMatchers.get();
		var presentation = vshaxe.taskPresentation;

		var commandGroups = [TaskGroup.Clean, null, TaskGroup.Build, null, TaskGroup.Test];
		var tasks = [];

		var args = [];
		if (limeVerbose)
		{
			args.push("-verbose");
		}

		if (vshaxe.enableCompilationServer && displayPort != null /*&& args.indexOf("--connect") == -1*/)
		{
			args.push("--connect");
			args.push(Std.string(displayPort));
		}

		for (item in targetItems)
		{
			for (command in limeCommands)
			{
				var task = createTask(getCommandArguments(command, item), args, presentation, problemMatchers);
				tasks.push(task);
			}
		}

		for (i in 0...limeCommands.length)
		{
			var command = limeCommands[i];
			var commandGroup = commandGroups[i];

			var task = createTask(getCommandArguments(command, targetItem), args, presentation, problemMatchers, commandGroup);
			var definition:LimeTaskDefinition = cast task.definition;
			definition.command = command;
			task.name = command + " (current)";
			tasks.push(task);
		}

		var task = createTask("run html5 -nolaunch", args, presentation, ["$lime-nolaunch"]);
		task.isBackground = true;
		tasks.push(task);

		var task = createTask("test html5 -nolaunch", args, presentation, ["$lime-nolaunch"]);
		task.isBackground = true;
		tasks.push(task);

		return tasks;
	}

	private function refresh():Void
	{
		checkHasProjectFile();

		if (hasProjectFile)
		{
			if (displayArgumentsProvider == null)
			{
				constructDisplayArgumentsProvider();
			}

			var oldLimeExecutable = limeExecutable;
			limeExecutable = getExecutable();
			var limeExecutableChanged = oldLimeExecutable != limeExecutable;

			if (isProviderActive && (!initialized || limeExecutableChanged))
			{
				if (!initialized)
				{
					initialize();
					construct();
				}

				updateDisplayArguments();
			}
		}

		if (!hasProjectFile || !isProviderActive)
		{
			deconstruct();
		}

		if (initialized)
		{
			updateTargetItems();
			updateStatusBarItems();
		}
	}

	private function registerDebugConfigurationProviders():Void
	{
		debug.registerDebugConfigurationProvider("chrome", this);
		debug.registerDebugConfigurationProvider("fdb", this);
		debug.registerDebugConfigurationProvider("hl", this);
		debug.registerDebugConfigurationProvider("hxcpp", this);
		debug.registerDebugConfigurationProvider("lime", this);
	}

	public function resolveDebugConfiguration(folder:Null<WorkspaceFolder>, config:DebugConfiguration,
			?token:CancellationToken):ProviderResult<DebugConfiguration>
	{
		if (config != null && config.type == null)
		{
			return null; // show launch.json
		}

		if (!hasProjectFile || !isProviderActive) return config;

		if (limeVersion < new SemVer(8, 0, 0))
		{
			var message = 'Lime debug support requires Lime 8.0.0 (or greater)';
			window.showWarningMessage(message);
			return config;
		}

		if (config != null && config.type == "lime")
		{
			var config:Dynamic = config;
			var target = getTargetItem().target;
			var outputFile = null;

			var targetLabel = "Unknown Target";
			if (limeTargets.exists(target))
			{
				targetLabel = limeTargets.get(target);
			}

			var supportedTargets = ["flash", "windows", "mac", "linux", "html5"];
			#if debug
			supportedTargets.push("hl");
			#end
			if (supportedTargets.indexOf(target) == -1)
			{
				window.showWarningMessage("Debugging " + targetLabel + " is not supported");
				return js.Lib.undefined;
			}

			switch (target)
			{
				case "hl":
					if (!hasExtension("HaxeFoundation.haxe-hl", true, "Debugging HashLink requires the \"HashLink Debugger\" extension"))
					{
						return js.Lib.undefined;
					}

				case "flash":
					if (!hasExtension("vshaxe.haxe-debug", true, "Debugging Flash requires the \"Flash Debugger\" extension"))
					{
						return js.Lib.undefined;
					}

				case "html5":
					if (!hasExtension("msjsdiag.debugger-for-chrome", true, "Debugging HTML5 requires the \"Debugger for Chrome\" extension"))
					{
						return js.Lib.undefined;
					}

				default:
					if (!hasExtension("vshaxe.hxcpp-debugger", true, "Debugging " + targetLabel + " requires the \"HXCPP Debugger\" extension"))
					{
						return js.Lib.undefined;
					}
			}

			var targetItem = getTargetItem();
			var commandLine = limeExecutable + " " + getCommandArguments("display", targetItem) + " --output-file";
			commandLine = StringTools.replace(commandLine, "-verbose", "");

			try
			{
				var output = ChildProcess.execSync(commandLine, {cwd: workspace.workspaceFolders[0].uri.fsPath});
				outputFile = StringTools.trim(Std.string(output));
			}
			catch (e:Dynamic)
			{
				trace(e);
			}

			config.preLaunchTask = "lime: build";

			switch (target)
			{
				case "flash":
					config.type = "fdb";
					config.program = "${workspaceFolder}/" + outputFile;

				case "hl":
					// TODO: Waiting for HL debugger to have a way to use a custom exec
					config.type = "hl";
					config.program = "${workspaceFolder}/" + Path.directory(outputFile) + "/hlboot.dat";
					config.exec = "${workspaceFolder}/" + outputFile;

				case "html5", "electron":
					// TODO: Get webRoot path from Lime
					// TODO: Get source maps working
					// TODO: Let Lime tell us what server and port
					// TODO: Support other debuggers? Firefox debugger?
					config.type = "chrome";
					config.url = "http://127.0.0.1:3000";
					// config.file = "${workspaceFolder}/" + Path.directory(outputFile) + "/index.html";
					config.sourceMaps = true;
					// config.smartStep = true;
					// config.internalConsoleOptions = "openOnSessionStart";
					config.webRoot = "${workspaceFolder}/" + Path.directory(outputFile);
					config.preLaunchTask = "lime: test html5 -nolaunch";

				case "windows", "mac", "linux":
					config.type = "hxcpp";
					config.program = "${workspaceFolder}/" + outputFile;

				default:
					return null;
			}
		}
		return config;
	}

	public function resolveTask(task:Task, ?token:CancellationToken):ProviderResult<Task>
	{
		// This method is never called
		// https://github.com/Microsoft/vscode/issues/33523
		// Hopefully this will work in the future for custom configured issues

		// TODO: Validate command name and target?
		// TODO: Get command list and target list from Lime?
		// var definition:LimeTaskDefinition = cast task.definition;

		// var commandArgs = getCommandArguments(definition.command, definition., true);

		// var vshaxe = getVshaxe();
		// var displayPort = vshaxe.displayPort;

		// if (vshaxe.enableCompilationServer && displayPort != null && commandArgs.indexOf("--connect") == -1)
		// {
		// 	commandArgs.push("--connect");
		// 	commandArgs.push(Std.string(displayPort));
		// }

		// // Resolve presentation or problem matcher?
		// // var problemMatchers = vshaxe.problemMatchers.get();
		// // var presentation = vshaxe.taskPresentation;

		// task.execution = new ShellExecution(limeExecutable + " " + commandArgs.join(" "),
		// 	{
		// 		cwd: workspace.workspaceFolders[0].uri.fsPath,
		// 		env: haxeEnvironment
		// 	});

		return task;
	}

	public function setTargetConfiguration(targetConfig:String):Void
	{
		context.workspaceState.update("lime.targetConfiguration", targetConfig);
		updateStatusBarItems();
		updateDisplayArguments();
	}

	private function updateDisplayArguments():Void
	{
		if (!hasProjectFile || !isProviderActive) return;

		var targetItem = getTargetItem();
		var commandLine = limeExecutable + " " + getCommandArguments("display", targetItem);
		commandLine = StringTools.replace(commandLine, "-verbose", "");

		ChildProcess.exec(commandLine, {cwd: workspace.workspaceFolders[0].uri.fsPath}, function(err, stdout:Buffer, stderror)
		{
			if (err != null && err.code != 0)
			{
				var message = 'Lime completion setup failed. Is the lime command available? Try running "lime setup" or changing the "lime.executable" setting.';
				var showFullErrorLabel = "Show Full Error";
				window.showErrorMessage(message, showFullErrorLabel).then(function(selection)
				{
					if (selection == showFullErrorLabel)
					{
						commands.executeCommand("workbench.action.toggleDevTools");
					}
				});
				trace(err);
			}
			else
			{
				displayArgumentsProvider.update(stdout.toString());
			}
		});
	}

	private function updateStatusBarItems():Void
	{
		if (hasProjectFile && isProviderActive)
		{
			var targetItem = getTargetItem();
			selectTargetItem.text = targetItem.label;
			selectTargetItem.show();

			limeVerbose = context.workspaceState.get("lime.verbose", false);

			if (limeVerbose)
			{
				toggleVerboseItem.text = "$(tasklist)";
				toggleVerboseItem.tooltip = "Toggle Lime Verbose Mode (Enabled)";
			}
			else
			{
				toggleVerboseItem.text = "$(list-unordered)";
				toggleVerboseItem.tooltip = "Toggle Lime Verbose Mode (Disabled)";
			}
			toggleVerboseItem.show();
		}
		else
		{
			selectTargetItem.hide();
			toggleVerboseItem.hide();
		}
	}

	private function updateTargetItems():Void
	{
		// TODO: Allow additional configurations

		limeTargets = ["android" => "Android", "flash" => "Flash", "html5" => "HTML5", "neko" => "Neko"];

		if (limeVersion >= new SemVer(8, 0, 0))
		{
			limeTargets.set("hl", "HashLink");
		}

		switch (Sys.systemName())
		{
			case "Windows":
				limeTargets.set("windows", "Windows");
				limeTargets.set("air", "AIR");
				limeTargets.set("electron", "Electron");

			case "Linux":
				limeTargets.set("linux", "Linux");

			case "Mac":
				limeTargets.set("mac", "macOS");
				limeTargets.set("ios", "iOS");
				limeTargets.set("tvos", "tvOS");
				limeTargets.set("air", "AIR");
				limeTargets.set("electron", "Electron");

			default:
		}

		var targets = workspace.getConfiguration("lime").get("targets", []);
		for (target in targets)
		{
			var enabled = Reflect.hasField(target, "enabled") ? target.enabled : true;
			var name = Reflect.hasField(target, "name") ? StringTools.trim(target.name) : null;
			var label = Reflect.hasField(target, "label") ? StringTools.trim(target.label) : null;

			if (!enabled)
			{
				if (name != null && limeTargets.exists(name))
				{
					limeTargets.remove(name);
				}
				else if (label != null)
				{
					for (key in limeTargets.keys())
					{
						if (limeTargets.get(key) == label)
						{
							limeTargets.remove(key);
							break;
						}
					}
				}
			}
			else if ((name != null && name.length > 0) || (label != null && label.length > 0))
			{
				if (label == null) label = name.charAt(0).toUpperCase() + name.substr(1);
				if (name == null) name = label.toLowerCase();
				limeTargets.set(name, label);
			}
		}

		targetItems = [];
		var buildTypes = ["Release" => null, "Debug" => ["-debug"], "Final" => ["-final"]];
		var types = workspace.getConfiguration("lime").get("buildTypes", []);
		for (type in types)
		{
			var enabled = Reflect.hasField(type, "enabled") ? type.enabled : true;
			var label = Reflect.hasField(type, "label") ? type.label : null;
			var args = Reflect.hasField(type, "args") ? type.args : null;

			if (!enabled)
			{
				if (label != null && buildTypes.exists(label))
				{
					buildTypes.remove(label);
				}
			}
			else
			{
				if (label != null && args != null)
				{
					buildTypes.set(label, args);
				}
			}
		}

		for (target in limeTargets.keys())
		{
			var targetLabel = limeTargets.get(target);

			for (type in buildTypes.keys())
			{
				targetItems.push(
					{
						label: targetLabel + ((type != null && type != "Release") ? " / " + type : ""),
						// description: "– " + target + (type != null ? " -" + type.toLowerCase() : ""),
						target: target,
						args: (type != null ? buildTypes.get(type) : null)
					});
			}
		}

		var additionalConfigs:Array<LimeTargetConfiguration> = workspace.getConfiguration("lime").get("targetConfigurations", []);
		var disabledConfigs = [];

		for (config in additionalConfigs)
		{
			if (Reflect.hasField(config, "enabled") && !config.enabled)
			{
				disabledConfigs.push(config.label);
				continue;
			}
			else if (!Reflect.hasField(config, "target") || config.target == null)
			{
				continue;
			}

			var target = config.target;
			var args = Reflect.hasField(config, "args") ? config.args : [];
			if (args == null) args = [];
			var command = StringTools.trim(target + " " + args.join(" "));
			var label = (Reflect.hasField(config, "label") && config.label != null ? config.label : command);

			for (item in targetItems)
			{
				if (item.label == label)
				{
					targetItems.remove(item);
					break;
				}
			}

			targetItems.push(
				{
					label: label,
					detail: command,
					target: target,
					args: args
				});
		}

		var i = 0;
		while (i < targetItems.length)
		{
			var targetItem = targetItems[i];
			if (disabledConfigs.indexOf(targetItem.label) > -1)
			{
				targetItems.splice(i, 1);
			}
			else
			{
				i++;
			}
		}

		targetItems.sort(function(a, b)
		{
			if (a.label < b.label) return -1;
			return 1;
		});
	}

	// Event Handlers

	private function toggleVerboseItem_onCommand():Void
	{
		limeVerbose = !limeVerbose;
		context.workspaceState.update("lime.verbose", limeVerbose);
		updateStatusBarItems();
	}

	private function selectTargetItem_onCommand():Void
	{
		var items = targetItems.copy();
		var targetItem = getTargetItem();
		items.moveToStart(function(item) return item == targetItem);
		window.showQuickPick(items, {matchOnDetail: true, placeHolder: "Select Lime Target Configuration"}).then(function(choice:TargetItem)
		{
			if (choice == null || choice == targetItem) return;
			setTargetConfiguration(choice.label);
		});
	}

	private function workspace_onDidChangeConfiguration(_):Void
	{
		refresh();
	}
}

@:enum private abstract LimeCommand(String) from String to String
{
	var CLEAN = "clean";
	var UPDATE = "update";
	var BUILD = "build";
	var RUN = "run";
	var TEST = "test";
}

private typedef LimeTargetConfiguration =
{
	@:optional var label:String;
	@:optional var target:String;
	@:optional var args:Array<String>;
	@:optional var enabled:Bool;
}

private typedef LimeTaskDefinition =
{
	> TaskDefinition,
	var command:String;
	@:optional var target:String;
}

private typedef TargetItem =
{
	> QuickPickItem,
	var target:String;
	var args:Array<String>;
}
