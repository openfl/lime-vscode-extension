package lime.extension;


import js.node.Buffer;
import js.node.ChildProcess;
import Vscode.*;
import vscode.*;


class Main {
	
	
	private var buildConfigItems:Array<BuildConfigItem>;
	private var context:ExtensionContext;
	private var displayArguments:Array<String> = [];
	private var editTargetFlagsItem:StatusBarItem;
	private var haxeServerAPI:Dynamic;
	private var haxeServerReady:Bool;
	private var lastLanguage:String;
	private var selectBuildConfigItem:StatusBarItem;
	private var selectTargetItem:StatusBarItem;
	private var targetItems:Array<TargetItem>;
	private var taskDisposable:Disposable;
	
	
	public function new (context:ExtensionContext) {
		
		this.context = context;
		
		//trace ("Hello from Lime extension");
		
		initialize ();
		construct ();
		
	}
	
	
	private function construct ():Void {
		
		selectTargetItem = window.createStatusBarItem (Left, 19);
		selectTargetItem.tooltip = "Select Target";
		selectTargetItem.command = "lime.selectTarget";
		context.subscriptions.push (selectTargetItem);
		
		selectBuildConfigItem = window.createStatusBarItem (Left, 18);
		selectBuildConfigItem.tooltip = "Select Build Configuration";
		selectBuildConfigItem.command = "lime.selectBuildConfig";
		context.subscriptions.push (selectBuildConfigItem);
		
		editTargetFlagsItem = window.createStatusBarItem (Left, 17);
		editTargetFlagsItem.tooltip = "Additional Command-Line Arguments";
		editTargetFlagsItem.command = "lime.editTargetFlags";
		context.subscriptions.push (editTargetFlagsItem);
		
		context.subscriptions.push (commands.registerCommand ("lime.selectTarget", selectTargetItem_onCommand));
		context.subscriptions.push (commands.registerCommand ("lime.selectBuildConfig", selectBuildConfigItem_onCommand));
		context.subscriptions.push (commands.registerCommand ("lime.editTargetFlags", editTargetFlagsItem_onCommand));
		
		context.subscriptions.push (workspace.onDidChangeConfiguration (workspace_onDidChangeConfiguration));
		context.subscriptions.push (window.onDidChangeActiveTextEditor (window_onDidChangeActiveTextEditor));
		
		workspace.registerTaskProvider ("lime", this);
		
		// TODO: Improve server API
		
		var vshaxe = extensions.getExtension("nadako.vshaxe");
		haxeServerAPI = vshaxe.exports;

		if (untyped !haxeServerAPI) {
			
			trace ("Warning: Haxe server API not available (probably using an incompatible vshaxe version)");
			
		} else {
			
			if (haxeServerAPI.isReady) {
				
				haxeServerAPI_onReady ();
				
			} else {
				
				haxeServerAPI.onReady = haxeServerAPI_onReady;
				
			}
			
		}
		
		updateStatusBarItems ();
		
	}
	
	
	private function createTask (description:String, command:String, ?group:TaskGroup) {
		
		var definition:TaskDefinition = cast {
			
			type: "lime",
			command: command
			
		}
		
		//var task = new Task (definition, description, "Lime");
		
		var commandLine = getCommandLine (command);
		var task = new Task (definition, commandLine.substr (5), "lime");
		task.execution = new ShellExecution (commandLine, { cwd: workspace.rootPath });
		//task.presentationOptions = { panel: TaskPanelKind.Shared };
		
		if (group != null) {
			
			task.group = group;
			
		}
		
		task.problemMatchers = [ "$haxe" ];
		return task;
		
	}
	
	
	public function getBuildConfigFlags ():String {
		
		return context.workspaceState.get ("lime.buildConfigFlags", "");
		
	}
	
	
	private function getCommandLine (command:String):String {
		
		var commandLine = "lime " + command;
		
		// TODO: Smarter logic
		if (command.indexOf (" ") == -1) {
			
			commandLine += " " + getTarget ();
			
		}
		
		var buildConfigFlags = getBuildConfigFlags ();
		if (buildConfigFlags != "") {
			
			commandLine += " " + buildConfigFlags;
			
		}
		
		var targetFlags = StringTools.trim (getTargetFlags ());
		if (targetFlags != "") {
			
			commandLine += " " + targetFlags;
			
		}
		
		return commandLine;
		
	}
	
	
	public function getTarget ():String {
		
		return context.workspaceState.get ("lime.target", "html5");
		
	}
	
	
	public function getTargetFlags ():String {
		
		return context.workspaceState.get ("lime.additionalTargetFlags", "");
		
	}
	
	
	private function initialize ():Void {
		
		// TODO: Check for workspace.getConfiguration ("lime").get ("projectFile");
		// TODO: Use Lime to check if directory is a Lime project if not found
		// TODO: Populate target items and build configurations from Lime
		
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
		
	}
	
	
	@:keep @:expose("activate") public static function activate (context:ExtensionContext) {
		
		new Main (context);
		
	}
	
	
	static function main () {}
	
	
	public function provideTasks (?token:CancellationToken):ProviderResult<Array<Task>> {
		
		var tasks = [
			createTask ("Clean", "clean", TaskGroup.Clean),
			createTask ("Update", "update"),
			createTask ("Build", "build", TaskGroup.Build),
			createTask ("Run", "run"),
			//createTask ("Test", "test", TaskGroup.Test),
			createTask ("Test", "test", untyped __js__('new vscode.TaskGroup ("test", "Test")')),
			createTask ("Rebuild", "rebuild", TaskGroup.Rebuild)
		];
		
		if (getTarget () != "html5") {
			
			tasks.push (createTask ("Rebuild", "rebuild tools", TaskGroup.Rebuild));
			
		}
		
		return tasks;
		
	}
	
	
	public function resolveTask (task:Task, ?token:CancellationToken):ProviderResult<Task> {
		
		var definition:Dynamic = task.definition;
		var command = definition.command;
		task.execution = new ShellExecution (getCommandLine (command), { cwd: workspace.rootPath });
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
		
		var buildConfigFlags = getBuildConfigFlags ();
		var targetFlags = getTargetFlags ();
		var commandLine = StringTools.trim ("lime display " + getTarget () + (buildConfigFlags != "" ? " " + buildConfigFlags : "") + (targetFlags != "" ? " " + targetFlags : ""));
		
		commandLine = StringTools.replace (commandLine, "-verbose", "");
		
		//trace ("Running display command: " + commandLine);
		
		try {
			
			ChildProcess.exec (commandLine, { cwd: workspace.rootPath }, function (err, stdout:Buffer, stderror) {
				
				try {
					
					var lines = stdout.toString ().split ("\n");
					var args = [];
					
					for (line in lines) {
						
						line = StringTools.trim (line);
						if (line != "") args.push (line);
						
					}
					
					if (displayArguments.length == args.length) {
						
						var equal = true;
						
						for (i in 0...args.length) {
							
							if (displayArguments[i] != args[i]) {
								
								equal = false;
								break;
								
							}
							
						}
						
						if (equal) return;
						
					}
					
					displayArguments = args;
					
					if (haxeServerReady) {
						
						haxeServerAPI.updateDisplayArguments (args);
						
					}
					
				} catch (e:Dynamic) {
					
					trace ("Error running display command: " + commandLine);
					trace (e);
					
				}
				
			});
			
		} catch (e:Dynamic) {
			
			trace ("Error running display command: " + commandLine);
			trace (e);
			
		}
		
	}
	
	
	private function updateStatusBarItems ():Void {
		
		//var hasEditor = (window.activeTextEditor != null);
		//var isDocument = hasEditor && languages.match({language: 'haxe', scheme: 'file'}, window.activeTextEditor.document) > 0;
		//var isRelatedPanel = hasEditor && (window.activeTextEditor.document:Dynamic).scheme != "file" && lastLanguage == "haxe";
		
		if (true /*&& (isDocument || isRelatedPanel)*/) {
			
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
			lastLanguage = "haxe";
			return;
			
		}
		
		lastLanguage = null;
		selectTargetItem.hide ();
		selectBuildConfigItem.hide ();
		editTargetFlagsItem.hide ();
		
	}
	
	
	
	
	// Event Handlers
	
	
	
	
	private function editTargetFlagsItem_onCommand ():Void {
		
		var flags = getTargetFlags ();
		window.showInputBox ({ prompt: "Additional Command-Line Arguments", value: flags + " ", valueSelection: [ flags.length + 1, flags.length + 1 ] }).then (function (value:String) {
			
			if (untyped !value) value = "";
			setTargetFlags (StringTools.trim (value));
			
		});
		
	}
	
	
	private function haxeServerAPI_onReady ():Void {
		
		haxeServerReady = true;
		updateDisplayArguments ();
		
	}
	
	
	private function selectBuildConfigItem_onCommand ():Void {
		
		var items = buildConfigItems;
		window.showQuickPick (items, { matchOnDescription: true, placeHolder: "Select Build Configuration"}).then (function (choice:BuildConfigItem) {
			
			// TODO: Update if target flags include a build configuration?
			
			if (choice == null || choice.flags == getBuildConfigFlags ())
				return;
				
			setBuildConfigFlags (choice.flags);
			
		});
		
	}
	
	
	private function selectTargetItem_onCommand ():Void {
		
		var items = targetItems;
		window.showQuickPick (items, { matchOnDescription: true, placeHolder: "Select Target" }).then (function (choice:TargetItem) {
			
			if (choice == null || choice.target == getTarget ())
				return;
			
			setTarget (choice.target);
			
		});
		
	}
	
	
	private function window_onDidChangeActiveTextEditor (_):Void {
		
		updateStatusBarItems ();
		
	}
	
	
	private function workspace_onDidChangeConfiguration (_):Void {
		
		updateStatusBarItems ();
		
	}
	
	
}


private typedef TargetItem = {
	>QuickPickItem,
	var target:String;
}


private typedef BuildConfigItem = {
	>QuickPickItem,
	var flags:String;
}