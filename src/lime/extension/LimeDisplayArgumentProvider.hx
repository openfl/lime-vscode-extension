package lime.extension;


//import vshaxe.api.DisplayArgumentProvider;


class LimeDisplayArgumentProvider /*extends DisplayArgumentProvider*/ {
	
	
	private var arguments:String;
	private var updateArgumentsCallback:String->Void;
	
	
	public function new () {
		
		//super ();
		
	}
	
	
	public /*override*/ function activate (provideArguments:String->Void):Void {
		
		updateArgumentsCallback = provideArguments;
		
		if (arguments != null) {
			
			updateArgumentsCallback (arguments);
			
		}
		
	}
	
	
	public /*override*/ function deactivate ():Void {
		
		updateArgumentsCallback = null;
		
	}
	
	
	public function update (arguments:String):Void {
		
		if (this.arguments != arguments) {
			
			this.arguments = arguments;
			
			if (updateArgumentsCallback != null) {
				
				updateArgumentsCallback (arguments);
				
			}
			
		}
		
	}
	
	
}