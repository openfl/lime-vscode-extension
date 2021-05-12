package lime.extension;

import js.lib.Promise;
import haxe.ds.ReadOnlyArray;
import js.node.Buffer;
import js.node.ChildProcess;
import js.node.Fs;
import sys.FileSystem;
import haxe.io.Path;
import haxe.DynamicAccess;
import Vscode.*;
import vscode.*;

using lime.extension.ArrayHelper;
using Lambda;
using StringTools;

class Main
{
	private static final DefaultProjectFiles:ReadOnlyArray<String> = ["project.xml", "Project.xml", "project.hxp", "project.lime"];
	private static var instance:Main;

	private var context:ExtensionContext;
	private var displayArgumentsProvider:DisplayArgsProvider;
	private var displayArgumentsProviderDisposable:Disposable;
	private var disposables:Array<{function dispose():Void;}> = [];
	private var editTargetFlagsItem:StatusBarItem;
	private var hasProjectFile:Bool;
	private var isProjectFileDirty:Bool = false;
	private var initialized:Bool;
	private var isProviderActive:Bool;
	private var selectTargetItem:StatusBarItem;
	private var targetItems:Array<TargetItem>;
	private var haxeEnvironment:DynamicAccess<String>;
	private var limeCommands:Array<LimeCommand>;
	private var limeExecutable:String;
	private var limeProjectFile:String;
	private var limeTargets:Map<String, String>;
	private var limeVersion = new SemVer(0, 0, 0);
	private var limeReadyProcess:js.node.child_process.ChildProcess;

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
				for (file in DefaultProjectFiles)
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
		selectTargetItem = window.createStatusBarItem(Left, 9);
		selectTargetItem.tooltip = "Select Lime Target Configuration";
		selectTargetItem.command = "lime.selectTarget";
		disposables.push(selectTargetItem);

		editTargetFlagsItem = window.createStatusBarItem(Left, 7);
		editTargetFlagsItem.command = "lime.editTargetFlags";
		disposables.push(editTargetFlagsItem);

		disposables.push(commands.registerCommand("lime.selectTarget", selectTargetItem_onCommand));
		disposables.push(commands.registerCommand("lime.editTargetFlags", editTargetFlagsItem_onCommand));
		disposables.push(commands.registerCommand("lime.refreshCodeCompletion", refreshCodeCompletion));
		disposables.push(tasks.registerTaskProvider("lime", this));
	}

	private function deconstruct():Void
	{
		for (disposable in disposables)
		{
			disposable.dispose();
		}

		selectTargetItem = null;
		editTargetFlagsItem = null;
		isProjectFileDirty = false;

		disposables = [];
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
			displayArgumentsProviderDisposable = api.registerDisplayArgumentsProvider("Lime", displayArgumentsProvider);
		}
	}

	private function createTask(definition:LimeTaskDefinition, name:String, command:String, additionalArgs:Array<String>,
			presentation:vshaxe.TaskPresentationOptions, problemMatchers:Array<String>, group:TaskGroup = null)
	{
		command = StringTools.trim(command);

		var shellCommand = limeExecutable + " " + command;
		if (additionalArgs != null) shellCommand += " " + additionalArgs.join(" ");

		var task = new Task(definition, TaskScope.Workspace, name, "lime");
		task.execution = new ShellExecution(shellCommand, {
			cwd: workspace.workspaceFolders[0].uri.fsPath,
			env: haxeEnvironment
		});

		if (group != null)
		{
			task.group = group;
		}

		task.problemMatchers = problemMatchers;
		task.presentationOptions = {
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
			return StringTools.trim(command + " " + projectFile + " " + target + " " + args.join(" "));
		}
		else
		{
			return StringTools.trim(command + " " + target + " " + args.join(" "));
		}
	}

	private function getCommandName(command:String, targetItem:TargetItem):String
	{
		var target = targetItem.target;
		var args = (targetItem.args != null ? targetItem.args.copy() : []);

		return StringTools.trim(command + " " + target + " " + args.join(" "));
	}

	private function getDebugArguments(targetItem:TargetItem, additionalArgs:Array<String> = null):Array<String>
	{
		var args = (targetItem.args != null ? targetItem.args.copy() : []);

		if (args != null && args.indexOf("-debug") > -1)
		{
			switch (targetItem.target)
			{
				case "windows", "mac", "linux":
					if (hasExtension("vshaxe.hxcpp-debugger"))
					{
						if (additionalArgs == null) additionalArgs = [];
						return ["--haxelib=hxcpp-debug-server"].concat(additionalArgs);
					}

				case "flash":
					if (additionalArgs == null) additionalArgs = [];
					return ["-Dfdb"].concat(additionalArgs);

				default:
			}
		}

		return additionalArgs;
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
		if (executable == "lime" && !Hasbin.sync(executable))
		{
			executable = "haxelib run lime";
		}
		return executable;
	}

	private function getLimeVersion():Void
	{
		try
		{
			var output = ChildProcess.execSync(limeExecutable + " -version", {cwd: workspace.workspaceFolders[0].uri.fsPath});
			var version = SemVer.parse(StringTools.trim(Std.string(output)));
			if (version != null)
			{
				limeVersion = version;
			}
		}
		catch (e:Dynamic)
		{
			limeVersion = new SemVer(0, 0, 0);
			trace(e);
		}
	}

	private function getProjectDirectory():String
	{
		var projectFile = getProjectFile();
		if (projectFile != "")
		{
			var path = Path.normalize(StringTools.trim(projectFile)).split("/");
			path.pop();
			// path.unshift(workspace.workspaceFolders[0].uri.fsPath);
			return path.join("/");
		}
		else
		{
			return workspace.workspaceFolders[0].uri.fsPath;
		}
	}

	public function getProjectFile():String
	{
		var config = workspace.getConfiguration("lime");

		if (config.has("projectFile"))
		{
			limeProjectFile = Std.string(config.get("projectFile"));
			if (limeProjectFile == "null") limeProjectFile = "";
		}
		else
		{
			limeProjectFile = "";
		}

		return limeProjectFile;
	}

	public function getTargetFlags():String
	{
		return context.workspaceState.get("lime.additionalTargetFlags", "");
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
				commands.getCommands().then(function(commandList)
				{
					if (commandList.indexOf("workbench.extensions.installExtension") > -1)
					{
						var installNowLabel = "Install Now";
						window.showErrorMessage(message, installNowLabel).then(function(selection)
						{
							if (selection == installNowLabel)
							{
								commands.executeCommand("workbench.extensions.installExtension", id);
							}
						});
					}
					else
					{
						window.showWarningMessage(message);
					}
				});
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

		var watcher = workspace.createFileSystemWatcher("**/*.{xml,hxp,lime}", false, false, false);
		context.subscriptions.push(watcher.onDidCreate(projectFileWatcher_onDidCreateOrDelete));
		context.subscriptions.push(watcher.onDidChange(projectFileWatcher_onDidChange));
		context.subscriptions.push(watcher.onDidDelete(projectFileWatcher_onDidCreateOrDelete));
		context.subscriptions.push(watcher);

		context.subscriptions.push(window.onDidChangeActiveTextEditor(window_onDidChangeActiveTextEditor));

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

	private function isProjectFile(uri:Uri)
	{
		var filePath = uri.fsPath;
		var rootPath = workspace.workspaceFolders[0].uri.fsPath;
		if (filePath.startsWith(rootPath))
		{
			filePath = filePath.substr(rootPath.length + 1); // relative path
		}
		return DefaultProjectFiles.indexOf(filePath) != -1 || Path.normalize(filePath) == Path.normalize(getProjectFile());
	}

	private function projectFileWatcher_onDidCreateOrDelete(uri:Uri)
	{
		if (isProjectFile(uri))
		{
			refresh();
		}
	}

	private function projectFileWatcher_onDidChange(uri:Uri)
	{
		if (isProjectFile(uri))
		{
			isProjectFileDirty = true;
		}
	}

	private function window_onDidChangeActiveTextEditor(editor:Null<TextEditor>)
	{
		if (!hasProjectFile || !isProviderActive || !isProjectFileDirty) return;
		if (editor == null || editor.document.languageId != "haxe") return;

		if (workspace.getConfiguration("lime").get("promptToRefreshCompletion", false))
		{
			// show a prompt once when we switch to a Haxe file and project file is dirty
			window.showInformationMessage("Project file changes detected, run `lime update` to refresh code completion?", "Yes", "No").then(function(choice)
			{
				if (choice == "Yes")
				{
					refreshCodeCompletion();
				}
			});
		}
		else
		{
			refreshCodeCompletion();
		}
		isProjectFileDirty = false;
	}

	private function refreshCodeCompletion()
	{
		window.withProgress({title: "Lime: Refreshing Code Completion...", location: ProgressLocation.Window}, function(_, _)
		{
			return new Promise(function(resolve, _)
			{
				var commandLine = limeExecutable + " " + getCommandArguments("update", getTargetItem());
				ChildProcess.execSync(commandLine, {cwd: workspace.workspaceFolders[0].uri.fsPath});
				updateDisplayArguments(() -> resolve(null));
			});
		});
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
			}
		];
	}

	public function provideTasks(?token:CancellationToken):ProviderResult<Array<Task>>
	{
		var targetItem = getTargetItem();
		var vshaxe = getVshaxe();
		var displayPort = vshaxe.displayPort;
		var problemMatchers = vshaxe.problemMatchers.copy();
		var presentation = vshaxe.taskPresentation;

		var commandGroups = [TaskGroup.Clean, null, TaskGroup.Build, null, TaskGroup.Test];
		var tasks = [];

		var args = [];
		var targetFlags = StringTools.trim(getTargetFlags());
		if (targetFlags != "")
		{
			// TODO: Handle argument list better
			args = args.concat(targetFlags.split(" "));
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
				var definition:LimeTaskDefinition = {
					"type": "lime",
					"command": command,
					"targetConfiguration": item.label
				};
				var task = createTask(definition, getCommandName(command, item), getCommandArguments(command, item), getDebugArguments(item, args),
					presentation, problemMatchers);
				tasks.push(task);
			}

			if (item.target == "html5")
			{
				for (command in ["run", "test"])
				{
					var definition:LimeTaskDefinition = {
						"type": "lime",
						"command": command,
						"targetConfiguration": item.label,
						"args": ["-nolaunch"]
					};
					var name = getCommandName(command, item);
					var command = getCommandArguments(command, item);
					if (command.indexOf("-nolaunch") == -1)
					{
						name += " -nolaunch";
						command += " -nolaunch";
					}
					var task = createTask(definition, name, command, args, presentation, ["$lime-nolaunch"]);
					task.isBackground = true;
					tasks.push(task);
				}
			}
		}

		for (i in 0...limeCommands.length)
		{
			var command = limeCommands[i];
			var commandGroup = commandGroups[i];

			var definition:LimeTaskDefinition = {
				"type": "lime",
				"command": command
			};
			var task = createTask(definition, getCommandName(command, targetItem), getCommandArguments(command, targetItem),
				getDebugArguments(targetItem, args), presentation, problemMatchers, commandGroup);
			task.name = command + " (active configuration)";
			tasks.push(task);
		}

		return tasks;
	}

	private function refresh():Void
	{
		var oldLimeProjectFile = limeProjectFile;
		checkHasProjectFile();
		var limeProjectFileChanged = oldLimeProjectFile != limeProjectFile;

		if (hasProjectFile)
		{
			if (displayArgumentsProvider == null)
			{
				constructDisplayArgumentsProvider();
			}

			var oldLimeExecutable = limeExecutable;
			limeExecutable = getExecutable();
			var limeExecutableChanged = oldLimeExecutable != limeExecutable;

			if (isProviderActive && (!initialized || limeExecutableChanged || limeProjectFileChanged) && isLimeReady())
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

		if (!hasProjectFile && displayArgumentsProviderDisposable != null)
		{
			displayArgumentsProviderDisposable.dispose();
			displayArgumentsProviderDisposable = null;
			displayArgumentsProvider = null;
		}

		if (initialized)
		{
			updateTargetItems();
			updateStatusBarItems();
		}
	}

	private function isLimeReady():Bool
	{
		if (limeReadyProcess != null)
		{
			return false;
		}
		var pathResult = ChildProcess.spawnSync("haxelib path lime", {shell: true});
		if (pathResult.status != null && pathResult.status != 0)
		{
			var installNowLabel = "Install Now";
			Vscode.window.showWarningMessage("Haxelib \"lime\" is required for this workspace. Would you like to install it?", installNowLabel)
				.then((buttonLabel) ->
				{
					if (buttonLabel == installNowLabel)
					{
						Vscode.window.withProgress({location: ProgressLocation.Window}, (progress, token) ->
						{
							progress.report({message: "Installing Lime…"});
							return new Promise((resolve, reject) ->
							{
								limeReadyProcess = ChildProcess.exec("haxelib install lime --quiet", (error, stdout, stderr) ->
								{
									limeReadyProcess = null;
									if (error == null)
									{
										// other platforms may require sudo, so
										// we can't setup automatically
										if (Sys.systemName() == "Windows")
										{
											progress.report({message: "Setting up Lime…"});
											limeReadyProcess = ChildProcess.exec("haxelib run lime setup", (error, stdout, stderr) ->
											{
												limeReadyProcess = null;
												resolve(null);
												if (error == null)
												{
													refresh();
												}
												else
												{
													Vscode.window.showErrorMessage("Lime setup failed.");
												}
											});
										}
										else
										{
											resolve(null);
											refresh();
										}
										return;
									}
									else
									{
										resolve(null);
										Vscode.window.showErrorMessage("Lime installation failed.");
									}
								});
							});
						});
					}
				});
			return false;
		}
		if (!Hasbin.sync("lime") && Sys.systemName() == "Windows")
		{
			// if lime was installed already, set up the alias, if needed.
			// this works on windows automatically. however, for mac and linux,
			// lime requires sudo to create the alias. in that case, the
			// extension will fall back to `haxelib run lime` instead
			Vscode.window.withProgress({location: ProgressLocation.Window}, (progress, token) ->
			{
				progress.report({message: "Setting up Lime alias…"});
				return new Promise((resolve, reject) ->
				{
					limeReadyProcess = ChildProcess.exec("haxelib run lime setup -alias", (error, stdout, stderr) ->
					{
						limeReadyProcess = null;
						resolve(null);
						if (error == null)
						{
							refresh();
						}
						else
						{
							Vscode.window.showErrorMessage("Lime setup alias failed.");
						}
					});
				});
			});
			return false;
		}
		return true;
	}

	private function registerDebugConfigurationProviders():Void
	{
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

		if (limeVersion < new SemVer(7, 3, 0))
		{
			var message = 'Lime debug support requires Lime 7.3.0 (or greater)';
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

			var supportedTargets = ["flash", "windows", "mac", "linux", "html5", "hl"];
			if (supportedTargets.indexOf(target) == -1)
			{
				window.showWarningMessage("Debugging " + targetLabel + " is not supported");
				return js.Lib.undefined;
			}

			var browserType = workspace.getConfiguration("lime").get("browser", "chrome");

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
					if (browserType == "firefox")
					{
						if (!hasExtension("firefox-devtools.vscode-firefox-debug", true,
							"Debugging HTML5 with Firefox requires the \"Debugger for Firefox\" extension"))
						{
							return js.Lib.undefined;
						}
					}
					else if (browserType == "edge")
					{
						if (!hasExtension("msjsdiag.debugger-for-edge", true, "Debugging HTML5 with Edge requires the \"Debugger for Edge\" extension"))
						{
							return js.Lib.undefined;
						}
					}
					else
					{
						if (!hasExtension("msjsdiag.debugger-for-chrome", true, "Debugging HTML5 requires the \"Debugger for Chrome\" extension"))
						{
							return js.Lib.undefined;
						}
					}

				default:
					if (!hasExtension("vshaxe.hxcpp-debugger", true, "Debugging " + targetLabel + " requires the \"HXCPP Debugger\" extension"))
					{
						return js.Lib.undefined;
					}
			}

			var targetItem = getTargetItem();
			var commandLine = limeExecutable + " " + getCommandArguments("display", targetItem);
			var additionalArgs = getDebugArguments(targetItem, null);
			if (additionalArgs != null) commandLine += " " + additionalArgs.join(" ");
			commandLine += " --output-file";
			commandLine = StringTools.replace(commandLine, "-verbose", "");

			try
			{
				var output = ChildProcess.execSync(commandLine, {cwd: workspace.workspaceFolders[0].uri.fsPath});
				outputFile = StringTools.trim(Std.string(output));
				var projectDirectory = getProjectDirectory();
				if (projectDirectory != "")
				{
					var hxml:String = Fs.readFileSync(outputFile, "UTF-8");
					hxml += "\n--cwd \"" + projectDirectory + "\"";
					Fs.writeFileSync(outputFile, hxml);
				}
			}
			catch (e:Dynamic)
			{
				trace(e);
			}

			if (!Reflect.hasField(config, "preLaunchTask"))
			{
				config.preLaunchTask = "lime: build (active configuration)";
			}

			switch (target)
			{
				case "flash":
					config.type = "fdb";
					config.program = "${workspaceFolder}/" + outputFile;

				case "hl":
					return resolveHLDebugConfiguration(config, outputFile);

				case "html5", "electron":
					// TODO: Get webRoot path from Lime
					// TODO: Get source maps working
					// TODO: Let Lime tell us what server and port
					// TODO: Support other debuggers? Firefox debugger?
					config.type = browserType;
					config.url = "http://127.0.0.1:3000";
					config.sourceMaps = true;
					config.smartStep = true;
					config.webRoot = "${workspaceFolder}/" + Path.directory(outputFile);

					// search for an existing "lime test" task
					var testTaskName = getCommandArguments("test", targetItem) + " -nolaunch";
					var existingTask = Vscode.tasks.taskExecutions.copy().find((item) ->
					{
						return item.task.definition.type == "lime" && item.task.name == testTaskName;
					});
					if (existingTask == null)
					{
						// if the "test" task doesn't exist yet, run it first
						config.preLaunchTask = "lime: " + testTaskName;
					}
					else
					{
						// if the "test" task is already active, run the "build" task instead
						// this will reuse the existing server
						config.preLaunchTask = "lime: " + getCommandArguments("build", targetItem);
					}

				case "windows", "mac", "linux":
					config.type = "hxcpp";
					config.program = "${workspaceFolder}/" + outputFile;

				default:
					return null;
			}
		}
		return config;
	}

	private function resolveHLDebugConfiguration(config:Dynamic, outputFile:String):ProviderResult<DebugConfiguration>
	{
		if (Sys.systemName() == "Mac")
		{
			// copied from https://github.com/vshaxe/hashlink-debugger/blob/master/src/Extension.hx
			final visitButton = "Visit GitHub Issue";
			Vscode.window.showErrorMessage("HashLink debugging on macOS is not supported yet.", visitButton).then(function(choice)
			{
				if (choice == visitButton)
				{
					Vscode.env.openExternal(Uri.parse("https://github.com/vshaxe/hashlink-debugger/issues/28"));
				}
			});
			return null;
		}

		config.type = "hl";
		config.cwd = "${workspaceFolder}/" + Path.directory(outputFile);
		config.program = config.cwd + "/hlboot.dat";

		return new Promise(function(resolve:DebugConfiguration->Void, reject)
		{
			getVshaxe().getActiveConfiguration().then(function(haxeConfig)
			{
				var classPaths = haxeConfig.classPaths.map(cp -> cp.path);

				var limePath = null;
				for (path in classPaths)
				{
					// TODO: figure out a nicer way to do this
					if (~/[\/\\]/g.split(path).indexOf("lime") != -1)
					{
						limePath = Path.directory(path);
					}
				}

				// TODO: figure out a nicer way to do this
				config.hl = Path.join([
					limePath,
					"templates/bin/hl",
					switch (Sys.systemName())
					{
						case "Windows":
							"windows/hl.exe";
						case "Linux":
							"linux/hl";
						case "Mac":
							"mac/hl";
						case other:
							throw 'unsupported OS $other';
					}
				]);
				if (!FileSystem.exists(config.hl))
				{
					throw "Unable to locate HL binary - maybe your Lime version is too old.";
				}

				config.classPaths = classPaths;
				resolve(config);
			}, function(error)
			{
				reject("Unable to retrieve active Haxe configuration: " + error);
			});
		});
	}

	public function resolveDebugConfigurationWithSubstitutedVariables(folder:Null<WorkspaceFolder>, debugConfiguration:DebugConfiguration,
			?token:CancellationToken):ProviderResult<DebugConfiguration>
	{
		return debugConfiguration;
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

	public function setTargetFlags(flags:String):Void
	{
		context.workspaceState.update("lime.additionalTargetFlags", flags);
		updateStatusBarItems();
		updateDisplayArguments();
	}

	private function updateDisplayArguments(?callback:() -> Void):Void
	{
		if (!hasProjectFile || !isProviderActive)
		{
			if (callback != null) callback();
			return;
		}

		var targetItem = getTargetItem();
		var commandLine = limeExecutable + " " + getCommandArguments("display", targetItem) + " -Ddisable-version-check";
		var additionalArgs = getDebugArguments(targetItem, null);
		if (additionalArgs != null) commandLine += " " + additionalArgs.join(" ");
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
				var hxml = stdout.toString();
				var projectDirectory = getProjectDirectory();
				if (projectDirectory != "")
				{
					hxml += "\n--cwd \"" + projectDirectory + "\"";
				}
				displayArgumentsProvider.update(hxml);
			}

			if (callback != null) callback();
		});
	}

	private function updateStatusBarItems():Void
	{
		if (hasProjectFile && isProviderActive)
		{
			var targetItem = getTargetItem();
			selectTargetItem.text = targetItem.label;
			selectTargetItem.show();

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
			editTargetFlagsItem.hide();
		}
	}

	private function updateTargetItems():Void
	{
		// TODO: Allow additional configurations

		limeTargets = ["android" => "Android", "flash" => "Flash", "html5" => "HTML5", "neko" => "Neko"];

		if (limeVersion >= new SemVer(7, 3, 0))
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
				targetItems.push({
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

			targetItems.push({
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
	@:optional var targetConfiguration:String;
	@:optional var args:Array<String>;
}

private typedef TargetItem =
{
	> QuickPickItem,
	var target:String;
	var args:Array<String>;
}
