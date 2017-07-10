package vshaxe.api;


extern typedef DisplayArgumentProvider = {
	
	public function activate (provideArguments:String->Void):Void;
	public function deactivate ():Void;
	
}