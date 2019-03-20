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

	private var buildConfigItems:Array<BuildConfigItem>;
	private var context:ExtensionContext;
	private var displayArgumentsProvider:LimeDisplayArgumentsProvider;
	private var disposables:Array<{function dispose():Void;}>;
	private var editTargetFlagsItem:StatusBarItem;
	private var hasProjectFile:Bool;
	private var initialized:Bool;
	private var isProviderActive:Bool;
	private var selectBuildConfigItem:StatusBarItem;
	private var selectTargetItem:StatusBarItem;
	private var targetItems:Array<TargetItem>;
	private var haxeEnvironment:DynamicAccess<String>;
	private var limeExecutable:String;
	private var limeVersion:SemVer = "0.0.0";

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
		selectTargetItem.tooltip = "Select Target";
		selectTargetItem.command = "lime.selectTarget";
		disposables.push(selectTargetItem);

		selectBuildConfigItem = window.createStatusBarItem(Left, 8);
		selectBuildConfigItem.tooltip = "Select Build Configuration";
		selectBuildConfigItem.command = "lime.selectBuildConfig";
		disposables.push(selectBuildConfigItem);

		editTargetFlagsItem = window.createStatusBarItem(Left, 7);
		editTargetFlagsItem.command = "lime.editTargetFlags";
		disposables.push(editTargetFlagsItem);

		disposables.push(commands.registerCommand("lime.selectTarget", selectTargetItem_onCommand));
		disposables.push(commands.registerCommand("lime.selectBuildConfig", selectBuildConfigItem_onCommand));
		disposables.push(commands.registerCommand("lime.editTargetFlags", editTargetFlagsItem_onCommand));

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
		selectBuildConfigItem = null;
		editTargetFlagsItem = null;

		disposables = null;
		initialized = false;
	}

	private function constructDisplayArgumentsProvider()
	{
		var api:Vshaxe = getVshaxe();

		displayArgumentsProvider = new LimeDisplayArgumentsProvider(api, function(isProviderActive)
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

	private function createTask(description:String, command:String, ?group:TaskGroup)
	{
		var definition:LimeTaskDefinition =
			{
				type: "lime",
				command: command
			}

		// var task = new Task (definition, description, "Lime");
		var args = getCommandArguments(command);
		var name = command;

		var vshaxe = getVshaxe();
		var displayPort = vshaxe.displayPort;
		if (getVshaxe().enableCompilationServer && displayPort != null && args.indexOf("--connect") == -1)
		{
			args.push("--connect");
			args.push(Std.string(displayPort));
		}

		var task = new Task(definition, TaskScope.Workspace, name, "lime");

		task.execution = new ShellExecution(limeExecutable + " " + args.join(" "), {cwd: workspace.workspaceFolders[0].uri.fsPath, env: haxeEnvironment});

		if (group != null)
		{
			task.group = group;
		}

		task.problemMatchers = vshaxe.problemMatchers.get();

		var presentation = vshaxe.taskPresentation;
		task.presentationOptions =
			{
				reveal: presentation.reveal,
				echo: presentation.echo,
				focus: presentation.focus,
				panel: presentation.panel,
				showReuseMessage: presentation.showReuseMessage,
				clear: presentation.clear
			};

		var target = getTarget();
		if (target == "html5" && command.indexOf("-nolaunch") > -1)
		{
			task.isBackground = true;
			task.problemMatchers = ["$lime-nolaunch"];
		}

		return task;
	}

	public function getBuildConfigFlags():String
	{
		var defaultFlags = "";
		var defaultBuildConfigLabel = workspace.getConfiguration("lime").get("defaultBuildConfiguration", "Release");
		var defaultBuildConfig = buildConfigItems.find(function(item) return item.label == defaultBuildConfigLabel);
		if (defaultBuildConfig != null)
		{
			defaultFlags = defaultBuildConfig.flags;
		}

		return context.workspaceState.get("lime.buildConfigFlags", defaultFlags);
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

	private function getCommandArguments(command:String):Array<String>
	{
		var args = command.split(" ");

		// TODO: Support rebuild tools (and other command with no project file argument)

		var target = getTarget();
		var debug = false;

		var projectFile = getProjectFile();
		if (projectFile != "") args.push(projectFile);
		args.push(target);

		var buildConfigFlags = getBuildConfigFlags();
		if (buildConfigFlags != "")
		{
			if (buildConfigFlags.indexOf("-debug") > -1) debug = true;
			// TODO: Handle argument list better
			args = args.concat(buildConfigFlags.split(" "));
		}

		var targetFlags = StringTools.trim(getTargetFlags());
		if (targetFlags != "")
		{
			// TODO: Handle argument list better
			args = args.concat(targetFlags.split(" "));
		}

		if (target == "windows" || target == "mac" || target == "linux")
		{
			// TODO: Update task when extension is installed?
			if (hasExtension("vshaxe.hxcpp-debugger"))
			{
				args.push("--haxelib=hxcpp-debug-server");
			}
		}
		else if (target == "flash" && debug)
		{
			args.push("-Dfdb");
		}

		return args;
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

	public function getTarget():String
	{
		var defaultTarget = "html5";
		var defaultTargetLabel = workspace.getConfiguration("lime").get("defaultTarget", "HTML5");
		var defaultTargetItem = targetItems.find(function(item) return item.label == defaultTargetLabel);
		if (defaultTargetItem != null)
		{
			defaultTarget = defaultTargetItem.target;
		}

		return context.workspaceState.get("lime.target", defaultTarget);
	}

	public function getTargetFlags():String
	{
		return context.workspaceState.get("lime.additionalTargetFlags", "");
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

		// TODO: Populate target items and build configurations from Lime

		targetItems = [
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
				target: "neko",
				label: "Neko",
				description: "",
			}
		];

		if (limeVersion >= new SemVer(8, 0, 0))
		{
			targetItems.push(
				{
					target: "hl",
					label: "HashLink (JIT)",
					description: "",
				});
		}

		targetItems.push(
			{
				target: "emscripten",
				label: "Emscripten",
				description: "",
			});

		switch (Sys.systemName())
		{
			case "Windows":
				targetItems.unshift(
					{
						target: "windows",
						label: "Windows",
						description: "",
					});

				targetItems.push(
					{
						target: "air",
						label: "AIR",
						description: "",
					});

				targetItems.push(
					{
						target: "electron",
						label: "Electron",
						description: "",
					});

			case "Linux":
				targetItems.unshift(
					{
						target: "linux",
						label: "Linux",
						description: "",
					});

			case "Mac":
				targetItems.unshift(
					{
						target: "mac",
						label: "macOS",
						description: "",
					});

				targetItems.unshift(
					{
						target: "ios",
						label: "iOS",
						description: "",
					});

				targetItems.push(
					{
						target: "air",
						label: "AIR",
						description: "",
					});

				targetItems.push(
					{
						target: "electron",
						label: "Electron",
						description: "",
					});
		}

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
		trace("provideDebugConfigurations");
		return [
			{
				"name": "Lime",
				"type": "lime",
				"request": "launch"
			}];
	}

	public function provideTasks(?token:CancellationToken):ProviderResult<Array<Task>>
	{
		var tasks = [
			createTask("Clean", "clean", TaskGroup.Clean),
			createTask("Update", "update"),
			createTask("Build", "build", TaskGroup.Build),
			createTask("Run", "run"),
			createTask("Test", "test", TaskGroup.Test),
		];

		var target = getTarget();
		if (target == "html5")
		{
			tasks.push(createTask("Run", "run -nolaunch"));
			tasks.push(createTask("Test", "test -nolaunch"));
		}

		// TODO: Detect Lime development build

		if (target != "html5" && target != "flash")
		{
			// tasks.push (createTask ("Rebuild", "rebuild", TaskGroup.Rebuild));
		}

		// tasks.push (createTask ("Rebuild", "rebuild tools", TaskGroup.Rebuild));

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
			var target = getTarget();
			var outputFile = null;

			var targetName = target;
			for (i in 0...targetItems.length)
			{
				var item = targetItems[i];
				if (item.target == target)
				{
					targetName = item.label;
					break;
				}
			}

			var supportedTargets = ["flash", "windows", "mac", "linux", "html5"];
			#if debug
			supportedTargets.push("hl");
			#end
			if (supportedTargets.indexOf(target) == -1)
			{
				window.showWarningMessage("Debugging " + targetName + " is not supported");
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
					if (!hasExtension("vshaxe.hxcpp-debugger", true, "Debugging " + targetName + " requires the \"HXCPP Debugger\" extension"))
					{
						return js.Lib.undefined;
					}
			}

			var commandLine = limeExecutable + " " + getCommandArguments("display").join(" ") + " --output-file";
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
					config.preLaunchTask = "lime: test -nolaunch";

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
		return task;
	}

	public function setBuildConfigFlags(flags:String):Void
	{
		context.workspaceState.update("lime.buildConfigFlags", flags);
		updateStatusBarItems();
		updateDisplayArguments();
	}

	public function setTarget(target:String):Void
	{
		context.workspaceState.update("lime.target", target);
		updateStatusBarItems();
		updateDisplayArguments();
	}

	public function setTargetFlags(flags:String):Void
	{
		context.workspaceState.update("lime.additionalTargetFlags", flags);
		updateStatusBarItems();
		updateDisplayArguments();
	}

	private function updateDisplayArguments():Void
	{
		if (!hasProjectFile || !isProviderActive) return;

		var commandLine = limeExecutable + " " + getCommandArguments("display").join(" ");
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
			var target = getTarget();

			for (i in 0...targetItems.length)
			{
				var item = targetItems[i];
				if (item.target == target)
				{
					selectTargetItem.text = item.label;
					selectTargetItem.show();
					break;
				}
			}

			var buildConfigFlags = getBuildConfigFlags();

			for (i in 0...buildConfigItems.length)
			{
				var item = buildConfigItems[i];
				if (item.flags == buildConfigFlags)
				{
					selectBuildConfigItem.text = item.label;
					selectBuildConfigItem.show();
					break;
				}
			}

			editTargetFlagsItem.text = "$(list-unordered)";
			editTargetFlagsItem.tooltip = "Edit Target Flags";
			var flags = getTargetFlags();
			if (flags.length != 0)
			{
				editTargetFlagsItem.tooltip += ' ($flags)';
			}
			editTargetFlagsItem.show();
		}
		else
		{
			selectTargetItem.hide();
			selectBuildConfigItem.hide();
			editTargetFlagsItem.hide();
		}
	}

	// Event Handlers
	private function editTargetFlagsItem_onCommand():Void
	{
		var flags = getTargetFlags();
		var value = if (flags.length == 0) "" else flags + " ";
		window.showInputBox({prompt: "Target Flags", value: value, valueSelection: [flags.length + 1, flags.length + 1]}).then(function(newValue:String)
		{
			if (newValue != null)
			{
				setTargetFlags(StringTools.trim(newValue));
			}
		});
	}

	private function selectBuildConfigItem_onCommand():Void
	{
		var items = buildConfigItems;
		items.moveToStart(function(item) return item.flags == getBuildConfigFlags());
		window.showQuickPick(items, {matchOnDescription: true, placeHolder: "Select Build Configuration"}).then(function(choice:BuildConfigItem)
		{
			// TODO: Update if target flags include a build configuration?

			if (choice == null || choice.flags == getBuildConfigFlags()) return;

			setBuildConfigFlags(choice.flags);
		});
	}

	private function selectTargetItem_onCommand():Void
	{
		var items = targetItems;
		items.moveToStart(function(item) return item.target == getTarget());
		window.showQuickPick(items, {matchOnDescription: true, placeHolder: "Select Target"}).then(function(choice:TargetItem)
		{
			if (choice == null || choice.target == getTarget()) return;

			setTarget(choice.target);
		});
	}

	private function workspace_onDidChangeConfiguration(_):Void
	{
		refresh();
	}
}

private typedef LimeTaskDefinition =
{
	> TaskDefinition,
	var command:String;
}

private typedef TargetItem =
{
	> QuickPickItem,
	var target:String;
}

private typedef BuildConfigItem =
{
	> QuickPickItem,
	var flags:String;
}
