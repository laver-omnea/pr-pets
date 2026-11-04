import PRPetsCore

/// Where each body part sits for one pose. Coordinates are in the sprite frame, y down, facing right.
struct PetSkeleton: Sendable {
    struct Leg: Sendable {
        let x: Int
        let top: Int
        let bottom: Int
        let isFarSide: Bool
    }

    enum Posture: Sendable { case standing, sitting, lying }

    let posture: Posture
    let body: (x: ClosedRange<Int>, y: ClosedRange<Int>)
    /// Top-left of the head box.
    let head: (x: Int, y: Int)
    let legs: [Leg]
    /// Where the tail joins the body.
    let tailRoot: (x: Int, y: Int)
    /// 0 or 1, alternates the tail's sway.
    let tailSway: Int
    let eyesClosed: Bool
    let headSize: (width: Int, height: Int)

    static let frameWidth = 30
    static let frameHeight = 24
    /// Lowest row a paw can touch. The outline sits one row below.
    static let groundRow = 22

    init(species: Species, build: BodyBuild, pose: PetPose) {
        let shape = Proportions(species: species, build: build)
        let (bodyX, bodyTop) = (shape.bodyX, shape.bodyTop)
        let ground = Self.groundRow
        let standingBodyBottom = ground - shape.legLength
        headSize = shape.headSize

        switch pose {
        case .stand, .standBlink, .walk1, .walk2, .walk3, .walk4, .run1, .run2, .startle:
            let gait = Self.gait(for: pose)
            let bodyBottom = standingBodyBottom - gait.lift
            let footRow = ground - gait.airborne
            posture = .standing
            body = (bodyX, (bodyTop - gait.lift)...bodyBottom)
            head = (bodyX.upperBound + shape.headOffset.x, bodyTop + shape.headOffset.y - gait.lift)
            let backX = bodyX.lowerBound + shape.legInset.back
            let frontX = bodyX.upperBound - shape.legInset.front
            legs = [
                Leg(x: backX + 1 + gait.farBack, top: bodyBottom + 1, bottom: footRow, isFarSide: true),
                Leg(x: frontX + 1 + gait.farFront, top: bodyBottom + 1, bottom: footRow, isFarSide: true),
                Leg(x: backX + gait.nearBack, top: bodyBottom + 1, bottom: footRow, isFarSide: false),
                Leg(x: frontX + gait.nearFront, top: bodyBottom + 1, bottom: footRow, isFarSide: false),
            ]
            tailRoot = (bodyX.lowerBound, bodyTop - gait.lift + 1)
            tailSway = gait.tailSway
            eyesClosed = pose == .standBlink
        case .sit, .sitBlink:
            posture = .sitting
            let sitTop = bodyTop - 1
            body = ((bodyX.lowerBound + shape.sittingInset)...bodyX.upperBound, sitTop...ground)
            head = (bodyX.upperBound + shape.headOffset.x - 1, sitTop + shape.headOffset.y)
            legs = [
                Leg(x: bodyX.upperBound, top: ground - 2, bottom: ground, isFarSide: true),
                Leg(x: bodyX.upperBound - 1, top: ground - 2, bottom: ground, isFarSide: false),
            ]
            tailRoot = (bodyX.lowerBound + 2, ground - 1)
            tailSway = 0
            eyesClosed = pose == .sitBlink
        case .sleep1, .sleep2:
            posture = .lying
            let breath = pose == .sleep2 ? 1 : 0
            let lyingTop = ground - shape.lyingDepth - breath
            body = ((bodyX.lowerBound - 1)...(bodyX.upperBound), lyingTop...ground)
            head = (bodyX.upperBound - 1, ground - shape.headSize.height + 1 - shape.lyingHeadLift)
            legs = [Leg(x: bodyX.upperBound + 4, top: ground, bottom: ground, isFarSide: false)]
            tailRoot = (bodyX.lowerBound - 1, ground - 1)
            tailSway = 0
            eyesClosed = true
        }
    }

    /// How a species is put together, standing.
    private struct Proportions {
        var bodyX: ClosedRange<Int>
        var bodyTop: Int
        var legLength = 2
        /// How far in from the back and front of the body the legs stand.
        var legInset = (back: 1, front: 1)
        /// How much narrower the body gets when sitting, taken off the back.
        var sittingInset = 2
        var headSize = (width: 7, height: 6)
        /// The head's top-left corner, relative to the front of the body and the top of the back.
        var headOffset = (x: -2, y: -6)
        /// Rows from the ground to the top of the back when lying down.
        var lyingDepth: Int
        /// How far the head rests above the ground when lying down.
        var lyingHeadLift = 0

        init(species: Species, build: BodyBuild) {
            switch (species, build) {
            case (.capybara, .chonky): (bodyX, bodyTop) = (7...19, 13)
            case (.capybara, _): (bodyX, bodyTop) = (8...19, 14)
            case (_, .slim): (bodyX, bodyTop) = (10...18, 17)
            case (_, .regular): (bodyX, bodyTop) = (10...18, 16)
            case (_, .chonky): (bodyX, bodyTop) = (9...19, 15)
            }
            lyingDepth = bodyTop < 16 ? 4 : 3
            if species == .capybara {
                // A long, flat-backed barrel on longish legs, with a big blocky head held up above the shoulders.
                legLength = 3
                legInset = (back: 1, front: 2)
                sittingInset = 4
                headSize = (width: 7, height: 5)
                headOffset = (x: -2, y: -2)
                lyingDepth = 4
                lyingHeadLift = 1
            }
        }
    }

    private struct Gait {
        var nearBack = 0, nearFront = 0, farBack = 0, farFront = 0
        var lift = 0
        var airborne = 0
        var tailSway = 0
    }

    private static func gait(for pose: PetPose) -> Gait {
        switch pose {
        case .walk1: Gait(nearBack: 1, nearFront: 1, farBack: -1, farFront: -1, tailSway: 1)
        case .walk2: Gait(lift: 1)
        case .walk3: Gait(nearBack: -1, nearFront: -1, farBack: 1, farFront: 1, tailSway: 1)
        case .walk4: Gait(lift: 1)
        case .run1: Gait(nearBack: -2, nearFront: 2, farBack: -1, farFront: 1, lift: 1, tailSway: 1)
        case .run2: Gait(nearBack: 1, nearFront: -1, farBack: 2, farFront: -2, lift: 2, airborne: 1)
        case .startle: Gait(nearBack: -1, nearFront: 1, lift: 2, airborne: 2, tailSway: 1)
        default: Gait()
        }
    }
}
