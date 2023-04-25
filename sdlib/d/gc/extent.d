module d.gc.extent;

import d.gc.base;
import d.gc.heap;
import d.gc.rbtree;
import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

alias ExtentTree = RBTree!(Extent, addrRangeExtentCmp);

alias PHNode = heap.Node!Extent;
alias RBNode = rbtree.Node!Extent;

struct Extent {
private:
	ulong bits;

public:
	void* addr;
	size_t sizeAndGen;

	import d.gc.hpd;
	HugePageDescriptor* hpd;

private:
	// TODO: Reuse this data to do something useful,
	// like garbage collection :P
	void* _pad;

	union Links {
		PHNode phnode;
		RBNode rbnode;
	}

	Links _links;

	import d.gc.bitmap;
	Bitmap!512 _slabData;

	this(uint arenaIndex, void* addr, size_t size, ubyte generation,
	     HugePageDescriptor* hpd, bool is_slab, ubyte sizeClass) {
		// FIXME: in contract.
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(sizeClass < ClassCount.Small,
		       "Invalid size class for small extent!");
		assert(isAligned(addr, PageSize), "Invalid alignment!");
		assert(isAligned(size, PageSize), "Invalid size!");

		this.addr = addr;
		this.sizeAndGen = size | generation;
		this.hpd = hpd;

		bits = is_slab;
		bits |= ulong(sizeClass) << 58;
		bits |= ulong(arenaIndex) << 36;

		import d.gc.bin;
		bits |= ulong(binInfos[sizeClass].slots) << 48;
	}

public:
	Extent* at(void* ptr, size_t size, HugePageDescriptor* hpd, bool is_slab,
	           ubyte sizeClass) {
		this =
			Extent(arenaIndex, ptr, size, generation, hpd, is_slab, sizeClass);
		return &this;
	}

	Extent* at(void* ptr, size_t size, HugePageDescriptor* hpd,
	           ubyte sizeClass) {
		return at(ptr, size, hpd, true, sizeClass);
	}

	Extent* at(void* ptr, size_t size, HugePageDescriptor* hpd) {
		// FIXME: Overload resolution doesn't cast this properly.
		return at(ptr, size, hpd, false, ubyte(0));
	}

	static fromSlot(uint arenaIndex, Base.Slot slot) {
		// FIXME: in contract
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(slot.address !is null, "Slot is empty!");
		assert(isAligned(slot.address, ExtentAlign),
		       "Invalid slot alignement!");

		auto e = cast(Extent*) slot.address;
		e.bits = ulong(arenaIndex) << 36;
		e.sizeAndGen = slot.generation;

		return e;
	}

	@property
	size_t size() const {
		return sizeAndGen & ~PageMask;
	}

	bool isHuge() const {
		return size > HugePageSize;
	}

	@property
	ubyte generation() const {
		return sizeAndGen & 0xff;
	}

	@property
	ref PHNode phnode() {
		return _links.phnode;
	}

	@property
	ref RBNode rbnode() {
		return _links.rbnode;
	}

	bool contains(void* ptr) const {
		return ptr >= addr && ptr < addr + size;
	}

	/**
	 * Slab features.
	 */
	bool isSlab() const {
		return (bits & 0x01) != 0;
	}

	@property
	ubyte sizeClass() const {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");

		ubyte sc = bits >> 58;

		// FIXME: out contract.
		assert(sc < ClassCount.Small);
		return sc;
	}

	@property
	uint arenaIndex() const {
		return (bits >> 36) & ArenaMask;
	}

	@property
	bool containsPointers() const {
		return (arenaIndex & 0x01) != 0;
	}

	@property
	auto arena() const {
		import d.gc.arena;
		return Arena.getInitialized(arenaIndex);
	}

	@property
	uint freeSlots() const {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");

		enum Mask = (1 << 10) - 1;
		return (bits >> 48) & Mask;
	}

	uint allocate() {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");
		assert(freeSlots > 0, "Slab is full!");

		scope(success) bits -= (1UL << 48);
		return slabData.setFirst();
	}

	void free(uint index) {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");
		assert(slabData.valueAt(index), "Slot is already free!");

		bits += (1UL << 48);
		slabData.clearBit(index);
	}

	@property
	ref Bitmap!512 slabData() {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");

		return _slabData;
	}
}

static assert(Extent.sizeof == ExtentSize, "Unexpected Extent size!");
static assert(Extent.sizeof == ExtentAlign, "Unexpected Extent alignment!");

ptrdiff_t addrExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto r = cast(size_t) rhs.addr;

	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}

ptrdiff_t addrRangeExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto rstart = cast(size_t) rhs.addr;
	auto rend = rstart + rhs.size;

	// We need to compare that way to avoid integer overflow.
	return (l >= rend) - (l < rstart);
}

ptrdiff_t unusedExtentCmp(Extent* lhs, Extent* rhs) {
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.generation) << 56;
	auto r = ulong(rhs.generation) << 56;

	l |= cast(size_t) lhs;
	r |= cast(size_t) rhs;

	return (l > r) - (l < r);
}

unittest contains {
	auto base = cast(void*) 0x56789abcd000;
	enum Size = 13 * PageSize;

	Extent e;
	e.addr = base;
	e.sizeAndGen = Size;

	assert(!e.contains(base - 1));
	assert(!e.contains(base + Size));

	foreach (i; 0 .. Size) {
		assert(e.contains(base + i));
	}
}

unittest allocfree {
	Extent e;
	e.at(null, PageSize, null, ubyte(0));

	assert(e.isSlab());
	assert(e.sizeClass == 0);
	assert(e.freeSlots == 512);

	assert(e.allocate() == 0);
	assert(e.freeSlots == 511);

	assert(e.allocate() == 1);
	assert(e.freeSlots == 510);

	assert(e.allocate() == 2);
	assert(e.freeSlots == 509);

	e.free(1);
	assert(e.freeSlots == 510);

	assert(e.allocate() == 1);
	assert(e.freeSlots == 509);

	assert(e.allocate() == 3);
	assert(e.freeSlots == 508);

	e.free(0);
	e.free(3);
	e.free(2);
	e.free(1);
	assert(e.freeSlots == 512);
}
