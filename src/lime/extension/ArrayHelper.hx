package lime.extension;


using Lambda;


class ArrayHelper {

	public static function moveToStart<T> (array:Array<T>, f:T->Bool) {
		
		var element = array.find(f);
		if (element != null) {
	
			array.remove(element);
			array.unshift(element);
	
		}
	
	}

}