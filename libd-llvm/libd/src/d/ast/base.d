module d.ast.base;

public import d.location;

class Node {
	Location location;
	
	this(Location location) {
		this.location = location;
		
		// import sdc.terminal;
		// outputCaretDiagnostics(location, typeid(this).toString());
	}
	
	invariant() {
		assert(location != Location.init, "node location must never be init");
	}
}
