internal protocol TreeComparer: class {
	associatedtype Element

	func compare(_ left: Element, to right: Element) -> ComparisonResult
	func testEquality(_ first: Element, _ second: Element) -> Bool
}

extension TreeComparer {
	func testEquality(_ first: Element?, _ second: Element?) -> Bool {
		guard let _first = first, let _second = second else {
			return first == nil && second == nil
		}
		return testEquality(_first, _second)
	}
}

internal protocol TreeProtocol: class, RandomAccessCollection {
	associatedtype Key
	associatedtype Value
	associatedtype Index

	@discardableResult
	func insert(_ value: Value, forKey key: Key) -> Index

	func removeNode(forKey key: Key)
}

internal final class Tree<Key, Value, Comparer: TreeComparer>: TreeProtocol, Hashable where Comparer.Element == Key {
	typealias Index = Int

	private var root: TreeNode<Key, Value>?
	private var cacheCount = 0
	private var cache: UnsafeMutablePointer<Unowned<TreeNode<Key, Value>>>?
	private let comparer: Comparer

	init(rootNode: TreeNode<Key, Value>? = nil, comparer: Comparer) {
		self.root = rootNode?.copy()
		self.comparer = comparer
		self.cache = nil
		self.cacheCount = 0
	}

	var hashValue: Int {
		return ObjectIdentifier(self).hashValue
	}

	var startIndex: Int {
		return 0
	}

	var endIndex: Int {
		if let root = root {
			return root.leftCount + root.rightCount + 1
		} else {
			return 0
		}
	}

	subscript(position: Int) -> TreeNode<Key, Value> {
		var next = root!
		var offset = position

		while true {
			if offset < next.leftCount {
				next = next.left!
				continue
			}

			offset -= next.leftCount
			if offset == 0 {
				return next
			}

			offset -= 1
			assert(offset < next.rightCount, "Index out of bound.")

			next = next.right!
		}
	}

	subscript(cached position: Int) -> TreeNode<Key, Value> {
		return cache!.advanced(by: position).pointee.object
	}

	func forEach(_ body: (TreeNode<Key, Value>) throws -> Void) rethrows {
		func iterate(node: TreeNode<Key, Value>, body: (TreeNode<Key, Value>) throws -> Void) rethrows {
			if let left = node.left {
				try iterate(node: left, body: body)
			}

			try body(node)

			if let right = node.right {
				try iterate(node: right, body: body)
			}
		}

		if let root = root {
			try iterate(node: root, body: body)
		}
	}

	func cacheUpdatingForEach(action: (TreeNode<Key, Value>) -> Void) {
		self.cache?.deinitialize(count: cacheCount)
		self.cache?.deallocate(capacity: cacheCount)

		cacheCount = count
		self.cache = UnsafeMutablePointer<Unowned<TreeNode<Key, Value>>>.allocate(capacity: cacheCount)
		var handle = cache!

		func iterate(node: TreeNode<Key, Value>, action: (TreeNode<Key, Value>) -> Void) {
			if let left = node.left {
				iterate(node: left, action: action)
			}

			handle.initialize(to: Unowned(object: node))
			handle = handle.successor()
			action(node)

			if let right = node.right {
				iterate(node: right, action: action)
			}
		}

		if let root = root {
			iterate(node: root, action: action)
		}
	}

	func updateCache() {
		cacheUpdatingForEach(action: { _ in })
	}

	@discardableResult
	func insert(_ value: Value, forKey key: Key) -> Int {
		let node = TreeNode(key: key, value: value)

		if let root = root {
			var next = root
			var offset = 0

			while true {
				switch comparer.compare(node.key, to: next.key) {
				case .orderedSame:
					fatalError()

				case .orderedAscending:
					if let left = next.left {
						next.leftCount += 1
						next = left
					} else {
						next.left = node
						next.leftCount = 1
						return offset
					}

				case .orderedDescending:
					if let right = next.right {
						next.rightCount += 1
						offset += next.leftCount + 1
						next = right
					} else {
						next.right = node
						next.rightCount = 1
						return offset + 1
					}
				}
			}
		} else {
			root = node
			return 0
		}
	}

	func removeAll() {
		root = nil
	}

	func remove(at position: Int) {
		var parent = root!
		var next = root!
		var offset = position

		while true {
			if offset < next.leftCount {
				next.leftCount -= 1
				parent = next
				next = next.left!
				continue
			}

			offset -= next.leftCount
			if offset == 0 {
				break
			}

			offset -= 1
			assert(offset < next.rightCount, "Index out of bound.")

			next.rightCount -= 1
			parent = next
			next = next.right!
		}

		// Assumption: `left` and `right` cannot be the same.
		let isLeft = comparer.testEquality(parent.left?.key, next.key)

		// Degree 0/1 nodes
		guard let left = next.left, let right = next.right else {
			if isLeft {
				parent.left = next.left ?? next.right
				parent.leftCount = parent.left?.count ?? 0
			} else if !comparer.testEquality(parent.key, next.key) {
				parent.right = next.left ?? next.right
				parent.rightCount = parent.right?.count ?? 0
			} else {
				root = next.left ?? next.right
			}
			return
		}

		// Degree 2 nodes
		if isLeft {
			var rightmostParent = right
			var rightmost = right
			while let next = rightmost.right {
				rightmostParent = rightmost
				rightmost = next
			}

			if !comparer.testEquality(rightmostParent.key, rightmost.key) {
				rightmostParent.right = rightmost.left
				rightmostParent.rightCount -= 1
			}

			rightmost.left = left
			rightmost.leftCount = left.count
			rightmost.right = right
			rightmost.rightCount = right.count

			if !comparer.testEquality(parent.key, next.key) {
				parent.left = rightmost
				parent.leftCount = rightmost.count
			} else {
				root = rightmost
			}
		} else {
			var leftmostParent = left
			var leftmost = left
			while let next = leftmost.left {
				leftmostParent = leftmost
				leftmost = next
			}

			if !comparer.testEquality(leftmostParent.key, leftmost.key) {
				leftmostParent.left = leftmost.right
				leftmostParent.leftCount -= 1
			}

			leftmost.left = left
			leftmost.leftCount = left.count
			leftmost.right = right
			leftmost.rightCount = right.count

			if !comparer.testEquality(parent.key, next.key) {
				parent.right = leftmost
				parent.rightCount = leftmost.count
			} else {
				root = leftmost
			}
		}
	}

	func removeNode(forKey key: Key) {
		remove(at: index(of: key)!)
	}

	func index(of key: Key) -> Int? {
		guard let root = root else {
			return nil
		}

		var next = root
		var offset = 0

		while true {
			switch comparer.compare(key, to: next.key) {
			case .orderedSame:
				return offset + root.leftCount

			case .orderedAscending:
				if let left = next.left {
					next = left
				} else {
					return nil
				}

			case .orderedDescending:
				if let right = next.right {
					next = right
					offset += root.leftCount + 1
				} else {
					return nil
				}
			}
		}
	}

	func index(after i: Index) -> Index {
		return i + 1
	}

	func index(before i: Index) -> Index {
		return i - 1
	}

	func index(_ i: Int, offsetBy n: Int) -> Int {
		return i + n
	}

	func distance(from start: Int, to end: Int) -> Int {
		return end - start
	}

	func copy() -> Tree {
		return Tree(rootNode: root, comparer: comparer)
	}

	static func == (left: Tree, right: Tree) -> Bool {
		return left === right
	}
}

extension Tree: CustomStringConvertible {
	var description: String {
		var nodes: [String] = []
		nodes.reserveCapacity(count)

		forEach { node in
			nodes.append("[\(node.key)] = [\(node.value)]")
		}

		return nodes.joined(separator: "\n")
	}
}

internal final class TreeNode<Key, Value> {
	let key: Key
	let value: Value

	fileprivate var left: TreeNode<Key, Value>?
	fileprivate var right: TreeNode<Key, Value>?
	fileprivate var leftCount = 0
	fileprivate var rightCount = 0

	fileprivate var count: Int {
		return leftCount + rightCount + 1
	}

	fileprivate init(key: Key, value: Value) {
		self.key = key
		self.value = value
	}

	func copy() -> TreeNode {
		let node = TreeNode(key: key, value: value)
		node.leftCount = leftCount
		node.rightCount = rightCount
		node.left = left?.copy()
		node.right = right?.copy()
		return node
	}
}

extension TreeProtocol where Value == () {
	@discardableResult
	func insert(_ key: Key) -> Index {
		return insert((), forKey: key)
	}
	
	func remove(_ key: Key) {
		removeNode(forKey: key)
	}
}

struct Unowned<Object: AnyObject> {
	unowned let object: Object
}
