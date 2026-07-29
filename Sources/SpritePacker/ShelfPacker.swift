import Foundation

struct PackingItem: Equatable {
    var name: String
    var size: PixelSize
}

struct PackingResult: Equatable {
    var size: PixelSize
    var frames: [String: PixelRect]
}

/// Packs rectangles without rotation using multiple MaxRects heuristics.
/// The type name is retained to avoid changing existing callers.
struct ShelfPacker {
    var padding: Int = 2
    var maximumDimension: Int = 16_384

    func pack(_ items: [PackingItem]) throws -> PackingResult {
        guard !items.isEmpty else {
            return PackingResult(size: PixelSize(width: 1, height: 1), frames: [:])
        }

        let minimumWidth = items.map(\.size.width).max() ?? 1
        let minimumHeight = items.map(\.size.height).max() ?? 1
        guard minimumWidth > 0, minimumHeight > 0,
              minimumWidth <= maximumDimension, minimumHeight <= maximumDimension else {
            throw SpritePackerError.imageTooLarge(items[0].name)
        }

        let widths = powersOfTwo(from: minimumWidth)
        let heights = powersOfTwo(from: minimumHeight)
        let candidates = widths.flatMap { width in
            heights.map { height in PixelSize(width: width, height: height) }
        }.sorted {
            let lhsArea = $0.width * $0.height
            let rhsArea = $1.width * $1.height
            if lhsArea != rhsArea { return lhsArea < rhsArea }

            let lhsSkew = abs($0.width - $0.height)
            let rhsSkew = abs($1.width - $1.height)
            if lhsSkew != rhsSkew { return lhsSkew < rhsSkew }
            return $0.width < $1.width
        }

        guard let initial = candidates.lazy.compactMap({
            attemptPacking(items, in: $0)
        }).first else {
            throw SpritePackerError.imageTooLarge(items[0].name)
        }

        var best = compact(initial)
        var step = nextPowerOfTwo(max(best.size.width, best.size.height)) / 2
        while step >= 1 {
            var improved = true
            while improved {
                improved = false
                for candidate in refinementCandidates(around: best.size, step: step) {
                    guard let packed = attemptPacking(items, in: candidate) else {
                        continue
                    }
                    let compacted = compact(packed)
                    if isBetterSize(compacted.size, than: best.size) {
                        best = compacted
                        improved = true
                        break
                    }
                }
            }
            step /= 2
        }
        return best
    }

    private func attemptPacking(
        _ items: [PackingItem],
        in candidate: PixelSize
    ) -> PackingResult? {
        for heuristic in PlacementHeuristic.allCases {
            // Dynamic selection can fill awkward holes that fixed insertion
            // orders miss.
            if let frames = arrange(
                items,
                in: candidate,
                heuristic: heuristic,
                dynamicallySelectingItems: true
            ) {
                return PackingResult(size: candidate, frames: frames)
            }

            // Greedy dynamic selection can also fragment free space too
            // early, so try several deterministic large-first orders.
            for orderedItems in itemOrders(items) {
                if let frames = arrange(
                    orderedItems,
                    in: candidate,
                    heuristic: heuristic,
                    dynamicallySelectingItems: false
                ) {
                    return PackingResult(size: candidate, frames: frames)
                }
            }
        }
        return nil
    }

    private func refinementCandidates(around size: PixelSize, step: Int) -> [PixelSize] {
        var candidates = Set<SizeKey>()
        for widthDelta in [-step, 0, step] {
            for heightDelta in [-step, 0, step]
            where widthDelta != 0 || heightDelta != 0 {
                let width = size.width + widthDelta
                let height = size.height + heightDelta
                guard width > 0, height > 0,
                      width <= maximumDimension, height <= maximumDimension else {
                    continue
                }
                let candidate = PixelSize(width: width, height: height)
                guard isBetterSize(candidate, than: size) else { continue }
                candidates.insert(SizeKey(width: width, height: height))
            }
        }
        return candidates.map {
            PixelSize(width: $0.width, height: $0.height)
        }.sorted {
            if $0.width * $0.height != $1.width * $1.height {
                return $0.width * $0.height < $1.width * $1.height
            }
            return abs($0.width - $0.height) < abs($1.width - $1.height)
        }
    }

    private func compact(_ result: PackingResult) -> PackingResult {
        guard let minX = result.frames.values.map(\.x).min(),
              let minY = result.frames.values.map(\.y).min(),
              let maxX = result.frames.values.map({ $0.x + $0.width }).max(),
              let maxY = result.frames.values.map({ $0.y + $0.height }).max() else {
            return result
        }
        let frames = result.frames.mapValues {
            PixelRect(
                x: $0.x - minX,
                y: $0.y - minY,
                width: $0.width,
                height: $0.height
            )
        }
        return PackingResult(
            size: PixelSize(width: maxX - minX, height: maxY - minY),
            frames: frames
        )
    }

    private func isBetterSize(_ lhs: PixelSize, than rhs: PixelSize) -> Bool {
        let lhsArea = lhs.width * lhs.height
        let rhsArea = rhs.width * rhs.height
        if lhsArea != rhsArea { return lhsArea < rhsArea }
        return abs(lhs.width - lhs.height) < abs(rhs.width - rhs.height)
    }

    private func arrange(
        _ items: [PackingItem],
        in atlas: PixelSize,
        heuristic: PlacementHeuristic,
        dynamicallySelectingItems: Bool
    ) -> [String: PixelRect]? {
        // Extending the virtual bounds by padding permits an image to touch the
        // right or bottom atlas edge while still reserving padding between images.
        var freeRects = [
            PixelRect(x: 0, y: 0, width: atlas.width + padding, height: atlas.height + padding),
        ]
        var remaining = items
        var frames: [String: PixelRect] = [:]

        while !remaining.isEmpty {
            var best: Placement?

            let itemIndices = dynamicallySelectingItems
                ? Array(remaining.indices)
                : [remaining.startIndex]
            for itemIndex in itemIndices {
                let item = remaining[itemIndex]
                let packedWidth = item.size.width + padding
                let packedHeight = item.size.height + padding
                for freeRect in freeRects where packedWidth <= freeRect.width && packedHeight <= freeRect.height {
                    let leftoverWidth = freeRect.width - packedWidth
                    let leftoverHeight = freeRect.height - packedHeight
                    let placement = Placement(
                        itemIndex: itemIndex,
                        rect: PixelRect(
                            x: freeRect.x,
                            y: freeRect.y,
                            width: packedWidth,
                            height: packedHeight
                        ),
                        scores: heuristic.scores(
                            leftoverWidth: leftoverWidth,
                            leftoverHeight: leftoverHeight,
                            freeRect: freeRect,
                            packedWidth: packedWidth,
                            packedHeight: packedHeight
                        ),
                        name: item.name
                    )
                    if best == nil || placement.isBetter(than: best!) {
                        best = placement
                    }
                }
            }

            guard let best else { return nil }
            let item = remaining.remove(at: best.itemIndex)
            frames[item.name] = PixelRect(
                x: best.rect.x,
                y: best.rect.y,
                width: item.size.width,
                height: item.size.height
            )
            freeRects = split(freeRects, around: best.rect)
        }
        return frames
    }

    private func itemOrders(_ items: [PackingItem]) -> [[PackingItem]] {
        let comparators: [(PackingItem, PackingItem) -> Bool] = [
            descending { $0.size.width * $0.size.height },
            descending { max($0.size.width, $0.size.height) },
            descending { $0.size.height },
            descending { $0.size.width },
            descending { $0.size.width + $0.size.height },
        ]
        return comparators.map { items.sorted(by: $0) }
    }

    private func descending(
        _ value: @escaping (PackingItem) -> Int
    ) -> (PackingItem, PackingItem) -> Bool {
        { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)
            if lhsValue != rhsValue { return lhsValue > rhsValue }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func split(_ freeRects: [PixelRect], around used: PixelRect) -> [PixelRect] {
        var result: [PixelRect] = []
        for free in freeRects {
            guard free.intersects(used) else {
                result.append(free)
                continue
            }

            if used.x > free.x {
                result.append(PixelRect(
                    x: free.x, y: free.y,
                    width: used.x - free.x, height: free.height
                ))
            }
            if used.maxX < free.maxX {
                result.append(PixelRect(
                    x: used.maxX, y: free.y,
                    width: free.maxX - used.maxX, height: free.height
                ))
            }
            if used.y > free.y {
                result.append(PixelRect(
                    x: free.x, y: free.y,
                    width: free.width, height: used.y - free.y
                ))
            }
            if used.maxY < free.maxY {
                result.append(PixelRect(
                    x: free.x, y: used.maxY,
                    width: free.width, height: free.maxY - used.maxY
                ))
            }
        }
        return removeContainedRects(result)
    }

    private func removeContainedRects(_ rects: [PixelRect]) -> [PixelRect] {
        rects.enumerated().compactMap { index, rect in
            let isContained = rects.enumerated().contains { otherIndex, other in
                index != otherIndex && other.contains(rect)
                    && (other != rect || otherIndex < index)
            }
            return isContained ? nil : rect
        }
    }

    private func powersOfTwo(from minimum: Int) -> [Int] {
        var value = nextPowerOfTwo(minimum)
        var values: [Int] = []
        while value <= maximumDimension {
            values.append(value)
            value *= 2
        }
        return values
    }

    private func nextPowerOfTwo(_ value: Int) -> Int {
        var result = 1
        while result < value { result *= 2 }
        return result
    }
}

private struct Placement {
    var itemIndex: Int
    var rect: PixelRect
    var scores: (Int, Int, Int)
    var name: String

    func isBetter(than other: Placement) -> Bool {
        if scores.0 != other.scores.0 { return scores.0 < other.scores.0 }
        if scores.1 != other.scores.1 { return scores.1 < other.scores.1 }
        if scores.2 != other.scores.2 { return scores.2 < other.scores.2 }
        return name.localizedStandardCompare(other.name) == .orderedAscending
    }
}

private enum PlacementHeuristic: CaseIterable {
    case bestShortSide
    case bestLongSide
    case bestArea
    case topLeft

    func scores(
        leftoverWidth: Int,
        leftoverHeight: Int,
        freeRect: PixelRect,
        packedWidth: Int,
        packedHeight: Int
    ) -> (Int, Int, Int) {
        let shortSide = min(leftoverWidth, leftoverHeight)
        let longSide = max(leftoverWidth, leftoverHeight)
        let areaWaste = freeRect.width * freeRect.height
            - packedWidth * packedHeight
        switch self {
        case .bestShortSide:
            return (shortSide, longSide, areaWaste)
        case .bestLongSide:
            return (longSide, shortSide, areaWaste)
        case .bestArea:
            return (areaWaste, shortSide, longSide)
        case .topLeft:
            return (freeRect.y + packedHeight, freeRect.x, shortSide)
        }
    }
}

private struct SizeKey: Hashable {
    var width: Int
    var height: Int
}
