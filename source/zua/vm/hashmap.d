module zua.vm.hashmap;
import zua.vm.engine;
import std.typecons;

private const double LOAD_FACTOR = 0.75;

private struct Bucket {
	size_t hash;
	Value key;
	Value value;
}

pragma(inline) size_t getHash(T)(T obj) {
	size_t res = hashOf(obj);
	if (res == 0) return 1; // shim to allow us to use a hash of 0 to store an empty bucket
	return res;
}

/** HashTable iterator */
struct HashTableIterator {

	private HashTable table;
	package size_t index;

	private void skipNulls() {
		Bucket* bucket = &table.buckets[index];
		while (bucket.hash == 0 || bucket.value.isNil) {
			index++;
			if (index >= table.buckets.length) return;
			bucket = &table.buckets[index];
		}
	}

	/** Check if range is empty */
	bool empty() {
		return index >= table.buckets.length;
	}

	/** Get the front element of this range */
	Tuple!(Value, Value) front() {
		Bucket* bucket = &table.buckets[index];
		return tuple(bucket.key, bucket.value);
	}

	/** Pop the front element of this range */
	void popFront() {
		index++;
		if (index >= table.buckets.length) return;
		skipNulls();
	}

}

// package struct HashTable {

// 	Value[Value] table;

// 	void initObj() {

// 	}

// 	size_t length() {
// 		return table.length;
// 	}

// 	/** Insert a value at a given key */
// 	void insert(Value key, Value value) {
// 		table[key] = value;
// 	}

// 	/** Lookup a value from a key */
// 	Value* lookup(Value key) {
// 		return key in table;
// 	}

// }

/** HashMap implementation for Lua tables */
package class HashTable {

	/** Get the number of key-value pairs in this map */
	size_t length;

	private Bucket[] buckets;

	private size_t capacityMask;

	/** Create a new hashmap */
	this() {
		buckets = newBuckets(16);
		capacityMask = buckets.length - 1;
	}

	private pragma(inline) Bucket[] newBuckets(size_t numOfBuckets) {
		return new Bucket[numOfBuckets];
	}

	private void resize() {
		Bucket[] prevBuckets = buckets;
		const numBuckets = buckets.length * 2;
		capacityMask = numBuckets - 1;
		buckets = newBuckets(numBuckets);

		length = 0;

		size_t newLength;
		foreach (i; 0 .. numBuckets / 2) {
			Bucket* bucket = &prevBuckets[i];
			if (bucket.hash != 0 && !bucket.value.isNil) {
				newLength++;
				insert(bucket.key, bucket.value);
			}
		}

		length = newLength;
	}

	private size_t probe(Value key, size_t hash = 0) {
		if (hash == 0) hash = getHash(key);
		size_t index = hash & capacityMask;
		Nullable!size_t tombstone;
		while (true) {
			Bucket* bucket = &buckets[index];

			if (bucket.hash == hash && bucket.key == key) return index;

			if (bucket.hash == 0) {
				if (!tombstone.isNull) return tombstone.get;
				return index;
			}

			if (bucket.value.isNil) tombstone = index.nullable;

			index = (index + 1) & capacityMask;
		}
	}

	/** Insert a value at a given key */
	void insert(Value key, Value value) {
		if (length + 1 > LOAD_FACTOR * buckets.length) resize();

		const size_t hash = getHash(key);
		const size_t index = probe(key, hash);

		Bucket newBucket;
		newBucket.hash = hash;
		newBucket.key = key;
		newBucket.value = value;

		if (buckets[index].hash == 0) {
			length++;
		}

		buckets[index] = newBucket;
	}

	/** Lookup a value from a key */
	Value* lookup(Value key) {
		if (length == 0) return null;

		const size_t index = probe(key);

		if (buckets[index].hash == 0 || buckets[index].value.isNil) {
			return null;
		}
		else {
			return &buckets[index].value;
		}
	}

	/** Return an iterator for this table */
	HashTableIterator iterator() {
		HashTableIterator res;
		res.index = 0;
		res.table = this;
		res.skipNulls();
		return res;
	}

	/** Return an iterator starting at, and including, a given key */
	HashTableIterator find(Value key) {
		const size_t index = probe(key);

		HashTableIterator res;
		res.index = index;
		res.table = this;
		return res;
	}

}

unittest {
	HashTable table = new HashTable;

	assert(table.length == 0);
	table.insert(Value(2), Value("hi"));

	auto hi = table.lookup(Value(2));
	assert(hi);
	assert(*hi == Value("hi"));

	foreach (d; 0 .. 100) {
		table.insert(Value(d), Value(d * 2 + 3));
	}

	foreach (d; 0 .. 100) {
		auto v = table.lookup(Value(d));
		assert(v);
		assert(*v == Value(d * 2 + 3));
	}

	HashTable table2 = new HashTable;

	foreach (d; 0 .. 10_000) {
		table2.insert(Value(d + 1.25), Value(d * 2 + 3));
	}

	foreach (d; 0 .. 10_000) {
		auto v = table2.lookup(Value(d + 1.25));
		assert(v);
		assert(*v == Value(d * 2 + 3));
	}

}