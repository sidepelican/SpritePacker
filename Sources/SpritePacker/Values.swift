struct PixelSize: Equatable {
    var width: Int
    var height: Int
}

struct PixelRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    
    var minX: Int { x }
    var minY: Int { y }
    var maxX: Int { x + width }
    var maxY: Int { y + height }

    func intersects(_ other: PixelRect) -> Bool {
        minX < other.maxX
        && maxX > other.minX
        && minY < other.maxY
        && maxY > other.minY
    }

    func contains(_ other: PixelRect) -> Bool {
        minX <= other.minX
        && minY <= other.minY
        && other.maxX <= maxX
        && other.maxY <= maxY
    }
}
