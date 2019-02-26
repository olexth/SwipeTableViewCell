//
//  SwipeTableViewCell.swift
//  
//
//  Created by Alex Golub on 2/26/19.
//

import UIKit

public enum CellRevealDirection: Int {
    case none = -1 // disables panning
    case both = 0
    case right = 1
    case left = 2
}

public struct CellAnimationType : OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    static let easeInOut   = CellAnimationType(rawValue: 0 << 16)
    static let easeIn      = CellAnimationType(rawValue: 1 << 16)
    static let easeOut     = CellAnimationType(rawValue: 2 << 16)
    static let easeLinear  = CellAnimationType(rawValue: 3 << 16)
    static let bounce      = CellAnimationType(rawValue: 4 << 16)
}

public protocol SwipeTableViewCellDelegate: class {
    func cellDidStartSwiping(cell: SwipeTableViewCell)
    func cellDidSwipeTo(point: CGPoint, velocity: CGPoint)
    func cellWillResetState(cell: SwipeTableViewCell, from point: CGPoint, animation: CellAnimationType, velocity: CGPoint)
    func cellDidResetState(cell: SwipeTableViewCell, from point: CGPoint, animation: CellAnimationType, velocity: CGPoint)
    
    ///**
    // *  Defaults to YES. The backView is recreated everytime the state is about to reset.
    // *
    // *  @param swipeTableViewCell The swipeable cell
    // *
    // *  @return A boolean value that informs the cell the cell whether to cleanup.
    // */
    func swipeCellShouldCleanupBackView(cell: SwipeTableViewCell) -> Bool
}

open class SwipeTableViewCell: UITableViewCell {

    // TODO: support internal doc format
    /**
     *  Customizable subview that is revealed when the user pans
     */
    var backView: UIView?
    
    /**
     *  Determines the direction that swiping is enabled for.
     *  Default is .both.
     */
    var revealDirection: CellRevealDirection = .both
    
    /**
     *  Determines the animation that occurs when panning ends.
     *  Default is .bounce.
     */
    var animationType: CellAnimationType = .bounce
    
    /**
     *  Determines the animation duration when the cell's contentView animates back.
     *  Default is 0.2f.
     */
    var animationDuration: TimeInterval = 0.2
    
    /**
     *  Override this property at any point to stop the cell contentView from animation back into place on touch ended. Default is true.
     *  This is useful in the swipeTableViewCellWillResetState:fromLocation: delegate method.
     *  Note: it will reset to true in prepareForReuse.
     */
    var shouldAnimateCellReset: Bool = true
    
    /**
     *  When panning/swiping the cell's location is set to exponentially decay. The elasticity (also know as rubber banding) matches that of a UIScrollView/UITableView.
     *  Default is true
     */
    var panElasticity: Bool = true
    
    /**
     *  This determines the exponential decay of the pan. By default it matches that of UIScrollView.
     *  Default is 0.55f.
     */
    var panElasticityFactor: CGFloat = 0.55
    
    /**
     *  When using panElasticity this property allows you to control at which point elasticity kicks in.
     *  Default is 0.0f
     */
    var panElasticityStartingPoint: CGFloat = 0.0
    
    /**
     *  The color of the back view, visible when swiping the cell's contentView
     *  Default is [UIColor colorWithWhite:0.92 alpha:1] // TODO:
     */
    var backViewBackgroundColor: UIColor = UIColor.init(white: 0.92, alpha: 1)
    
    /**
     *  The methods declared by the SwipeTableViewCellDelegate protocol allows you to respond
     *  to optional messages from the cell regarding it's interaction and animation behaviour
     */
    weak var delegate: SwipeTableViewCellDelegate?
    
    // MARK: - Init
    
    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        initialize()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
        
    }
    
    // TODO:
    private func initialize() {
        // We need to set the contentView's background color, otherwise the sides are clear on the swipe and animations
        contentView.backgroundColor = .white

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        let background = UIView(frame: self.frame)
        background.backgroundColor = .white
        backgroundView = background
    }
    
    open override func prepareForReuse() {
        super.prepareForReuse()
        shouldAnimateCellReset = true
    }
    
    // MARK: - GestureRecognizer Delegate
    
    open override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        
        if revealDirection != .none {
            let translation = panGesture.translation(in: superview)
            return (abs(translation.x) / abs(translation.y) > 1) ? true : false
        } else {
            return false
        }
    }
    
    @objc private func handlePanGesture(panGestureRecognizer: UIPanGestureRecognizer) {
        let translation = panGestureRecognizer.translation(in: panGestureRecognizer.view)

        let velocity = panGestureRecognizer.velocity(in: panGestureRecognizer.view)
        var panOffset = translation.x
        if panElasticity {
            if (abs(translation.x) > panElasticityStartingPoint) {
                let width = frame.width
                let offset = abs(translation.x)
                panOffset = (offset * panElasticityFactor * width) / (offset * panElasticityFactor + width)
                panOffset *= translation.x < 0 ? -1.0 : 1.0
                if (panElasticityStartingPoint > 0) {
                    panOffset = translation.x > 0 ? panOffset + panElasticityStartingPoint / 2 : panOffset - self.panElasticityStartingPoint / 2
                }
            }
        }
        
        let actualTranslation = CGPoint(x: panOffset, y: translation.y)
        if panGestureRecognizer.state == .began && panGestureRecognizer.numberOfTouches > 0 {
            didStartSwiping()
            animateContentViewFor(point: actualTranslation, velocity: velocity)
        } else if panGestureRecognizer.state == .changed && panGestureRecognizer.numberOfTouches > 0 {
            animateContentViewFor(point: actualTranslation, velocity: velocity)
        } else {
            resetCellFrom(point: actualTranslation, velocity: velocity)
        }
    }
    
    private func didStartSwiping() {
        delegate?.cellDidStartSwiping(cell: self)
        
        backView = UIView()
        backView?.backgroundColor = backViewBackgroundColor
        backView?.translatesAutoresizingMaskIntoConstraints = false
        backgroundView?.addSubview(backView!) // TODO: remove force unwrap
        
        let VConstraints = NSLayoutConstraint.constraints(withVisualFormat: "V:|[_backView]|",
                                                          options: [],
                                                          metrics: nil,
                                                          views: ["" : backView!])
        let HConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:|[_backView]|",
                                                          options: [],
                                                          metrics: nil,
                                                          views: ["" : backView!])
        backgroundView?.addConstraints(VConstraints)
        backgroundView?.addConstraints(HConstraints)
    }
    
    // MARK: - Gesture Animations
    
    private func animateContentViewFor(point: CGPoint, velocity: CGPoint) {
        if (point.x > 0 && revealDirection == .left) || (point.x < 0 && revealDirection == .right) || revealDirection == .both {
            contentView.frame = contentView.bounds.offsetBy(dx: point.x, dy: 0)
            
            delegate?.cellDidSwipeTo(point: point, velocity: velocity)
        } else if (point.x > 0 && revealDirection == .right) || (point.x < 0 && revealDirection == .left) {
            contentView.frame = contentView.bounds.offsetBy(dx: 0, dy: 0)
        }
    }
    
    private func resetCellFrom(point: CGPoint, velocity: CGPoint) {
        delegate?.cellWillResetState(cell: self, from: point, animation: animationType, velocity: velocity)
        
        // TODO: change to guard
        if !shouldAnimateCellReset {
            return
        }
        // TODO: change to guard
        if (revealDirection == .left && point.x < 0) || (revealDirection == .right && point.x > 0) {
            return
        }
        if animationType == .bounce {
            UIView.animate(withDuration: animationDuration,
                           delay: 0,
                           usingSpringWithDamping: 0.7,
                           initialSpringVelocity: point.x / 5,
                           options: .allowUserInteraction,
                           animations: {
                            self.contentView.frame = self.contentView.bounds
            }) { _ in
                let shouldCleanupBackView = self.delegate?.swipeCellShouldCleanupBackView(cell: self) ?? true
                if shouldCleanupBackView {
                    self.cleanupBackView()
                }

                self.delegate?.cellDidResetState(cell: self, from: point, animation: self.animationType, velocity: velocity)
            }
        } else {
            UIView.animate(withDuration: animationDuration,
                           delay: 0,
                           options: UIView.AnimationOptions(rawValue: UInt(animationType.rawValue)),
                           animations: {
                            self.contentView.frame = self.contentView.bounds.offsetBy(dx: 0, dy: 0)
            }) { _ in
                let shouldCleanupBackView = self.delegate?.swipeCellShouldCleanupBackView(cell: self) ?? true
                if shouldCleanupBackView {
                    self.cleanupBackView()
                }
                
                self.delegate?.cellDidResetState(cell: self, from: point, animation: self.animationType, velocity: velocity)
            }
        }
    }
    
    private func cleanupBackView() {
        backView?.removeFromSuperview()
        backView = nil
    }
}
