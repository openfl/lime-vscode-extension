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


class Main {
	
	
	private static var instance:Main;
	
	private var buildConfigItems:Array<BuildConfigItem>;
	private var context:ExtensionContext;
	private var displayArgumentsProvider:LimeDisplayArgumentsProvider;
	private var disposables:Array<{ function dispose():Void; }>;
	private var editTargetFlagsItem:StatusBarItem;
	private var hasProjectFile:Bool;
	private var initialized:Bool;
	private var isProviderActive:Bool;
	private var selectBuildConfigItem:StatusBarItem;
	private var selectTargetItem:StatusBarItem;
	private var targetItems:Array<TargetItem>;
	private var haxeEnvironment:DynamicAccess<String>;
	
	
	public function new (context:ExtensionContext) {
		
		this.context = context;
		
		context.subscriptions.push (workspace.onDidChangeConfiguration (workspace_onDidChangeConfiguration));
		refresh ();

	}


	private function checkHasProjectFile ():Void {
		
		hasProjectFile = false;
		
		try {
			
			if (getProjectFile () != "") {
				
				hasProjectFile = true;
				
			}
			
			if (!hasProjectFile) {
				
				var rootPath = workspace.rootPath;
				
				if (rootPath != null) {
					
					// TODO: support custom project file references
					
					var files = [ "project.xml", "Project.xml", "project.hxp", "project.lime" ];
					
					for (file in files) {
						
						if (FileSystem.exists (rootPath + "/" + file)) {
							
							hasProjectFile = true;
							break;
							
						}
						
					}
					
				}
				
			}
			
		}
		
	}
	
	
	private function construct ():Void {
		
		disposables = [];
		
		selectTargetItem = window.createStatusBarItem (Left, 9);
		selectTargetItem.tooltip = "Select Target";
		selectTargetItem.command = "lime.selectTarget";
		disposables.push (selectTargetItem);
		
		selectBuildConfigItem = window.createStatusBarItem (Left, 8);
		selectBuildConfigItem.tooltip = "Select Build Configuration";
		selectBuildConfigItem.command = "lime.selectBuildConfig";
		disposables.push (selectBuildConfigItem);
		
		editTargetFlagsItem = window.createStatusBarItem (Left, 7);
		editTargetFlagsItem.tooltip = "Edit Target Flags";
		editTargetFlagsItem.command = "lime.editTargetFlags";
		disposables.push (editTargetFlagsItem);
		
		disposables.push (commands.registerCommand ("lime.selectTarget", selectTargetItem_onCommand));
		disposables.push (commands.registerCommand ("lime.selectBuildConfig", selectBuildConfigItem_onCommand));
		disposables.push (commands.registerCommand ("lime.editTargetFlags", editTargetFlagsItem_onCommand));
		
		disposables.push (workspace.registerTaskProvider ("lime", this));
		
	}
	
	
	private function deconstruct ():Void {
		
		if (disposables == null) {
			
			return;
			
		}
		
		for (disposable in disposables) {
			
			disposable.dispose ();
			
		}
		
		selectTargetItem = null;
		selectBuildConfigItem = null;
		editTargetFlagsItem = null;
		
		disposables = null;
		initialized = false;
		
	}
	
	
	private function constructDisplayArgumentsProvider () {
		
		var api:Vshaxe = getVshaxe ();
		
		displayArgumentsProvider = new LimeDisplayArgumentsProvider (api, function (isProviderActive) {
			
			this.isProviderActive = isProviderActive;
			refresh ();
			
		});
		
		if (untyped !api) {
			
			trace ("Warning: Haxe language server not available (using an incompatible vshaxe version)");
			
		} else {
			
			api.registerDisplayArgumentsProvider ("Lime", displayArgumentsProvider);
			
		}
		
	}
	

	private inline function getVshaxe ():Vshaxe {
		
		return extensions.getExtension ("nadako.vshaxe").exports;
	
	}

	
	private function createTask (description:String, command:String, ?group:TaskGroup) {
		
		var definition:LimeTaskDefinition = {
			
			type: "lime",
			command: command
			
		}
		
		//var task = new Task (definition, description, "Lime");
		var args = getCommandArguments (command);
		var name = args.join (" ");
		
		var vshaxe = getVshaxe ();
		var displayPort = vshaxe.displayPort;
		if (getVshaxe ().enableCompilationServer && displayPort != null && args.indexOf ("--connect") == -1) {
			
			args.push ("--connect");
			args.push (Std.string (displayPort));
			
		}
		
		var task = new Task (definition, name, "lime");
		
		task.execution = new ShellExecution (getCommand () + " " + args.join (" "), { cwd: workspace.workspaceFolders[0].uri.fsPath, env: haxeEnvironment });
		
		if (group != null) {
			
			task.group = group;
			
		}
		
		task.problemMatchers = vshaxe.problemMatchers.get ();

		var presentation = vshaxe.taskPresentation;
		task.presentationOptions = {
			reveal: presentation.reveal,
			echo: presentation.echo,
			focus: presentation.focus,
			panel: presentation.panel
		};
		return task;
		
	}
	
	
	public function getBuildConfigFlags ():String {
		
		var defaultFlags = "";
		var defaultBuildConfigLabel = workspace.getConfiguration ("lime").get ("defaultBuildConfiguration", "Release");
		var defaultBuildConfig = buildConfigItems.find (function(item) return item.label == defaultBuildConfigLabel);
		if (defaultBuildConfig != null) {

			defaultFlags = defaultBuildConfig.flags;
			
		}

		return context.workspaceState.get ("lime.buildConfigFlags", defaultFlags);
		
	}
	

	private function getCommand ():String {

		var command = workspace.getConfiguration ("lime").get ("command");
		return if (command == null) "lime" else command;
	
	}

	
	private function getCommandArguments (command:String):Array<String> {
		
		var args = [ command ];
		
		// TODO: Support rebuild tools (and other command with no project file argument)
		
		var projectFile = getProjectFile ();
		if (projectFile != "") args.push (projectFile);
		args.push (getTarget ());
		
		var buildConfigFlags = getBuildConfigFlags ();
		if (buildConfigFlags != "") {
			
			// TODO: Handle argument list better
			args = args.concat (buildConfigFlags.split (" "));
			
		}
		
		var targetFlags = StringTools.trim (getTargetFlags ());
		if (targetFlags != "") {
			
			// TODO: Handle argument list better
			args = args.concat (targetFlags.split (" "));
			
		}
		
		return args;
		
	}
	
	
	public function getProjectFile ():String {
		
		var config = workspace.getConfiguration ("lime");
		
		if (config.has ("projectFile")) {
			
			var projectFile = Std.string (config.get ("projectFile"));
			if (projectFile == "null") projectFile = "";
			return projectFile;
			
		} else {
			
			return "";
			
		}
		
	}
	
	
	public function getTarget ():String {
		
		var defaultTarget = "html5";
		var defaultTargetLabel = workspace.getConfiguration ("lime").get ("defaultTarget", "HTML5");
		var defaultTargetItem = targetItems.find (function(item) return item.label == defaultTargetLabel);
		if (defaultTargetItem != null) {

			defaultTarget = defaultTargetItem.target;

		}

		return context.workspaceState.get ("lime.target", defaultTarget);
		
	}
	
	
	public function getTargetFlags ():String {
		
		return context.workspaceState.get ("lime.additionalTargetFlags", "");
		
	}
	
	
	private function initialize ():Void {
		
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
			},
			{
				target: "emscripten",
				label: "Emscripten",
				description: "",
			}
		];
		
		switch (Sys.systemName()) {
			
			case "Windows":
				
				targetItems.unshift ({
					target: "windows",
					label: "Windows",
					description: "",
				});
				
				targetItems.push ({
					target: "air",
					label: "AIR",
					description: "",
				});
			
			case "Linux":
				
				targetItems.unshift ({
					target: "linux",
					label: "Linux",
					description: "",
				});
			
			case "Mac":
				
				targetItems.unshift ({
					target: "mac",
					label: "macOS",
					description: "",
				});
				
				targetItems.unshift ({
					target: "ios",
					label: "iOS",
					description: "",
				});
				
				targetItems.push ({
					target: "air",
					label: "AIR",
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
		
		getVshaxe ().haxeExecutable.onDidChangeConfiguration (function (_) updateHaxeEnvironment ());
		updateHaxeEnvironment ();
		
		initialized = true;
		
	}
	
	private function updateHaxeEnvironment () {
		
		var haxeConfiguration = getVshaxe ().haxeExecutable.configuration;
		var env = new DynamicAccess ();
		
		for (field in Reflect.fields (haxeConfiguration.env)) {
			
			env[field] = haxeConfiguration.env[field];
			
		}
		
		if (!haxeConfiguration.isCommand) {
			
			var separator = Sys.systemName () == "Windows" ? ";" : ":";
			env["PATH"] = Path.directory (haxeConfiguration.executable) + separator + Sys.getEnv("PATH");
			
		}
		
		haxeEnvironment = env;
		
	}
	
	
	@:keep @:expose("activate") public static function activate (context:ExtensionContext) {
		
		instance = new Main (context);
		
	}
	
	
	@:keep @:expose("deactivate") public static function deactivate () {
		
		instance.deconstruct ();
		
	}
	
	
	static function main () {}
	
	
	public function provideTasks (?token:CancellationToken):ProviderResult<Array<Task>> {
		
		var tasks = [
			createTask ("Clean", "clean", TaskGroup.Clean),
			createTask ("Update", "update"),
			createTask ("Build", "build", TaskGroup.Build),
			createTask ("Run", "run"),
			createTask ("Test", "test", TaskGroup.Test),
		];
		
		var target = getTarget ();
		
		// TODO: Detect Lime development build
		
		if (target != "html5" && target != "flash") {
			
			//tasks.push (createTask ("Rebuild", "rebuild", TaskGroup.Rebuild));
			
		}
		
		//tasks.push (createTask ("Rebuild", "rebuild tools", TaskGroup.Rebuild));
		
		return tasks;
		
	}
	
	
	private function refresh ():Void {
		
		checkHasProjectFile ();
		
		if (hasProjectFile) {
			
			if (displayArgumentsProvider == null) {
				
				constructDisplayArgumentsProvider ();
				
			}
			
			if (isProviderActive && !initialized) {
				
				if (!initialized) {
					
					initialize ();
					construct ();
					
				}
				
				updateDisplayArguments ();
				
			}
			
		}
		
		if (!hasProjectFile || !isProviderActive) {
			
			deconstruct();
			
		}
		
		if (initialized) {
			
			updateStatusBarItems ();
			
		}
		
	}
	
	
	public function resolveTask (task:Task, ?token:CancellationToken):ProviderResult<Task> {
		
		return task;
		
	}
	
	
	public function setBuildConfigFlags (flags:String):Void {
		
		context.workspaceState.update ("lime.buildConfigFlags", flags);
		updateStatusBarItems ();
		updateDisplayArguments ();
		
	}
	
	
	public function setTarget (target:String):Void {
		
		context.workspaceState.update ("lime.target", target);
		updateStatusBarItems ();
		updateDisplayArguments ();
		
	}
	
	
	public function setTargetFlags (flags:String):Void {
		
		context.workspaceState.update ("lime.additionalTargetFlags", flags);
		updateDisplayArguments ();
		
	}
	
	
	private function updateDisplayArguments ():Void {
		
		if (!hasProjectFile || !isProviderActive) return;
		
		var commandLine = getCommand () + " " + getCommandArguments ("display").join (" ");
		commandLine = StringTools.replace (commandLine, "-verbose", "");

		ChildProcess.exec (commandLine, { cwd: workspace.workspaceFolders[0].uri.fsPath }, function (err, stdout:Buffer, stderror) {
			
			if (err != null && err.code != 0) {
	
				var message = 'Lime completion setup failed. Is the lime command available? Try running "lime setup" or changing the "lime.command" setting.';
				window.showErrorMessage (message, "Show Full Error").then (function (_) {

					commands.executeCommand ("workbench.action.toggleDevTools");

				});
				trace (err);

			} else {

				displayArgumentsProvider.update (stdout.toString ());

			}

		});
		
	}
	
	
	private function updateStatusBarItems ():Void {
		
		if (hasProjectFile && isProviderActive) {
			
			var target = getTarget ();
			
			for (i in 0...targetItems.length) {
				
				var item = targetItems[i];
				if (item.target == target) {
					
					selectTargetItem.text = item.label;
					selectTargetItem.show ();
					break;
					
				}
				
			}
			
			var buildConfigFlags = getBuildConfigFlags ();
			
			for (i in 0...buildConfigItems.length) {
				
				var item = buildConfigItems[i];
				if (item.flags == buildConfigFlags) {
					
					selectBuildConfigItem.text = item.label;
					selectBuildConfigItem.show ();
					break;
					
				}
				
			}
			
			editTargetFlagsItem.text = "$(list-unordered)";
			editTargetFlagsItem.show ();
			
		} else {
			
			selectTargetItem.hide ();
			selectBuildConfigItem.hide ();
			editTargetFlagsItem.hide ();
			
		}
		
	}
	
	
	
	
	// Event Handlers
	
	
	
	
	private function editTargetFlagsItem_onCommand ():Void {
		
		var flags = getTargetFlags ();
		window.showInputBox ({ prompt: "Target Flags", value: flags + " ", valueSelection: [ flags.length + 1, flags.length + 1 ] }).then (function (value:String) {
			
			if (untyped !value) value = "";
			setTargetFlags (StringTools.trim (value));
			
		});
		
	}
	
	
	private function selectBuildConfigItem_onCommand ():Void {
		
		var items = buildConfigItems;
		items.moveToStart(function (item) return item.flags == getBuildConfigFlags ());
		window.showQuickPick (items, { matchOnDescription: true, placeHolder: "Select Build Configuration"}).then (function (choice:BuildConfigItem) {
			
			// TODO: Update if target flags include a build configuration?
			
			if (choice == null || choice.flags == getBuildConfigFlags ())
				return;
				
			setBuildConfigFlags (choice.flags);
			
		});
		
	}
	
	
	private function selectTargetItem_onCommand ():Void {
		
		var items = targetItems;
		items.moveToStart(function (item) return item.target == getTarget ());
		window.showQuickPick (items, { matchOnDescription: true, placeHolder: "Select Target" }).then (function (choice:TargetItem) {
			
			if (choice == null || choice.target == getTarget ())
				return;
			
			setTarget (choice.target);
			
		});
		
	}
	
	
	private function workspace_onDidChangeConfiguration (_):Void {
		
		refresh ();
		
	}
	
	
}


private typedef LimeTaskDefinition = {
	>TaskDefinition,
	var command:String;
}


private typedef TargetItem = {
	>QuickPickItem,
	var target:String;
}


private typedef BuildConfigItem = {
	>QuickPickItem,
	var flags:String;
}
