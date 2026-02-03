import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Direction for the swipe-to-dismiss gesture.
enum SwipeDirection {
  /// Swipe from left to right (default iOS-style back gesture)
  leftToRight,

  /// Swipe from right to left
  rightToLeft,

  /// Allow swiping in both directions
  both,
}

CustomTransitionPage<T> buildIosSwipeTransition<T>({
  required Widget child,
  required GoRouterState state,
  bool maintainState = true,
  bool fullscreenDialog = false,
  int swipeDuration = 350,
  SwipeDirection swipeDirection = SwipeDirection.leftToRight,
  double edgeWidth = 20.0
}) {
  Duration transitionDuration = Duration(milliseconds: swipeDuration);
  return CustomTransitionPage<T>(
    key: state.pageKey,
    name: state.name,
    child: child,
    maintainState: maintainState,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: transitionDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return _IosSwipeTransition(
        transitionDuration: transitionDuration,
        routeAnimation: animation as ProxyAnimation,
        secondaryAnimation: secondaryAnimation,
        swipeDirection: swipeDirection,
        edgeWidth: edgeWidth,
        child: child,
      );
    },
  );
}

class _IosSwipeTransition extends StatefulWidget {
  const _IosSwipeTransition({
    required this.routeAnimation,
    required this.secondaryAnimation,
    required this.child,
    required this.transitionDuration,
    required this.swipeDirection,
    required this.edgeWidth
  });

  final ProxyAnimation routeAnimation;
  final Animation<double> secondaryAnimation;
  final Widget child;
  final Duration transitionDuration;
  final SwipeDirection swipeDirection;
  final double edgeWidth;

  @override
  State<_IosSwipeTransition> createState() => _IosSwipeTransitionState();
}

class _IosSwipeTransitionState extends State<_IosSwipeTransition> {
  bool _isDragging = false;
  bool _isPopping = false;
  bool _isAnimating = false;

  /// Tracks the current drag direction during a gesture.
  /// Positive = left-to-right, Negative = right-to-left
  double _currentDragDirection = 0;

  /// Lazy access to the underlying animation controller.
  ///
  /// Returns the parent AnimationController if available, otherwise null.
  AnimationController? get _controller {
    final anim = widget.routeAnimation;
    final parent = anim.parent;
    if (parent is AnimationController) {
      return parent;
    }
    return null;
  }

  /// Determines if swipe-to-dismiss gesture is allowed.
  ///
  /// Returns true if the router can navigate back.
  bool get _canSwipe {
    final router = GoRouter.of(context);
    return router.canPop();
  }

  /// Gets the appropriate animation based on current state.
  ///
  /// Returns linear animation during dragging and canceling for direct control,
  /// or curved animation for smooth transitions otherwise.
  Animation<double> get _effectiveAnimation {
    if (!_isDragging && !_isAnimating) {
      // Use curved animation for normal navigation
      final c = _controller;
      if (c == null) return widget.routeAnimation;

      return CurvedAnimation(
        parent: c,
        curve: Curves.easeInOut,
        reverseCurve: Curves.easeInOut,
      );
    }

    // Use linear animation during drag and gesture animations
    return _controller ?? widget.routeAnimation;
  }

  /// Gets the curved secondary animation for the previous page.
  Animation<double> get _effectiveSecondaryAnimation {
    return CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([
            _effectiveAnimation,
            _effectiveSecondaryAnimation,
          ]),
          builder: (context, _) {
            final anim = _effectiveAnimation.value;
            final anim2 = _effectiveSecondaryAnimation.value;

            // Apply corner radius only when transitioning
            final radius = anim == 1.0 ? 0.0 : topPadding;

            // Calculate horizontal offset with parallax effect
            // Direction depends on swipe direction setting
            double offsetX;
            double compensation;

            if (widget.swipeDirection == SwipeDirection.rightToLeft ||
                (widget.swipeDirection == SwipeDirection.both &&
                    _currentDragDirection < 0)) {
              // Right-to-left: page slides out to the left
              offsetX = -(1.0 - anim) * width;
              compensation = -0.25 * width * anim2;
            } else {
              // Left-to-right (default iOS): page slides out to the right
              offsetX = (1.0 - anim) * width;
              compensation = 0.25 * width * anim2;
            }

            final finalOffset = offsetX - compensation;

            return HeroMode(
              enabled: !_isDragging,
              child: Transform.translate(
                offset: Offset(finalOffset.clamp(-width, width), 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: _buildSwipeGesture(context, widget.child, width),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Builds a gesture detector that handles horizontal swipe-to-dismiss gestures.
  ///
  /// This wraps the provided [child] with gesture detection that allows users
  /// to swipe horizontally to navigate back. The gesture respects the page's
  /// transition animation and prevents race conditions.
  ///
  /// Returns the [child] unchanged if [_canSwipe] is false.
Widget _buildSwipeGesture(BuildContext context, Widget child, double width) {
  if (!_canSwipe) return child;

  return Stack(
    children: [
      child,
      // Invisible edge detector on the left side
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: widget.edgeWidth,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (details) => _handleDragStart(context),
          onHorizontalDragUpdate: (details) => _handleDragUpdate(details, width),
          onHorizontalDragEnd: (details) => _handleDragEnd(context, details),
          onHorizontalDragCancel: () => _handleDragCancel(context),
        ),
      ),
    ],
  );
}

  /// Handles the start of a horizontal drag gesture.
  ///
  /// Stops any ongoing animation and notifies the navigator that a user gesture
  /// has begun. This is blocked if a pop or animation is already in progress.
  void _handleDragStart(BuildContext context) {
    // Block if a pop or animation is already in progress
    if (_isPopping || _isAnimating) return;

    final controller = _controller;
    if (controller == null) return;

    // Stop any ongoing animation
    controller.stop();

    if (mounted) {
      setState(() => _isDragging = true);
    }

    // Notify the navigator that a user gesture has started
    Navigator.of(context).didStartUserGesture();
  }

  /// Updates the animation progress based on horizontal drag movement.
  ///
  /// Converts the drag delta into a fraction of the screen width and updates
  /// the animation controller value accordingly. The value is clamped between
  /// 0.0 and 1.0.
  ///
  /// This is blocked if a pop or animation is already in progress.
  void _handleDragUpdate(DragUpdateDetails details, double width) {
    // Block if a pop or animation is in progress
    if (_isPopping || _isAnimating) return;

    final controller = _controller;
    if (controller == null || !_isDragging) return;

    final delta = details.primaryDelta ?? 0.0;
    final fraction = delta / width;

    // Track drag direction (accumulate to determine overall direction)
    _currentDragDirection += delta;

    // Determine if this drag direction is valid based on swipeDirection setting
    final isLeftToRight = delta > 0;
    final isRightToLeft = delta < 0;

    bool isValidDirection = false;
    switch (widget.swipeDirection) {
      case SwipeDirection.leftToRight:
        isValidDirection = isLeftToRight || controller.value < 1.0;
        break;
      case SwipeDirection.rightToLeft:
        isValidDirection = isRightToLeft || controller.value < 1.0;
        break;
      case SwipeDirection.both:
        isValidDirection = true;
        break;
    }

    if (!isValidDirection) return;

    // For right-to-left swipe, invert the fraction
    final adjustedFraction =
        (widget.swipeDirection == SwipeDirection.rightToLeft ||
                (widget.swipeDirection == SwipeDirection.both &&
                    _currentDragDirection < 0))
            ? fraction // Right-to-left: positive delta decreases animation
            : -fraction; // Left-to-right: positive delta decreases animation (original behavior)

    // Update controller value based on drag distance
    controller.value = (controller.value + adjustedFraction).clamp(0.0, 1.0);
  }

  /// Handles the end of a horizontal drag gesture.
  ///
  /// Determines whether to pop the route or cancel based on:
  /// - Drag velocity (>300 pixels/second triggers pop)
  /// - Current progress (<70% triggers pop)
  ///
  /// If either condition is met, initiates a pop. Otherwise, animates back
  /// to the original position.
  ///

  void _handleDragEnd(BuildContext context, DragEndDetails details) {
    // Block if already processing a gesture
    if (_isPopping || _isAnimating) {
      _isDragging = false;
      _currentDragDirection = 0;
      return;
    }

    final controller = _controller;
    if (controller == null || !_isDragging) return;

    final velocity = details.velocity.pixelsPerSecond.dx;
    final progress = controller.value;

    // Determine if velocity direction matches the allowed swipe direction
    bool velocityMatchesDirection = false;
    switch (widget.swipeDirection) {
      case SwipeDirection.leftToRight:
        velocityMatchesDirection = velocity > 300;
        break;
      case SwipeDirection.rightToLeft:
        velocityMatchesDirection = velocity < -300;
        break;
      case SwipeDirection.both:
        velocityMatchesDirection = velocity.abs() > 300;
        break;
    }

    // Pop if: fast swipe in correct direction OR dragged past 30% point
    final shouldPop = velocityMatchesDirection || progress < 0.7;

    if (shouldPop) {
      _performPop(context, controller);
    } else {
      _cancelPop(context, controller);
    }

    _currentDragDirection = 0;
  }

  /// Handles cancellation of a horizontal drag gesture.
  ///
  /// This occurs when the gesture is interrupted (e.g., another gesture takes
  /// over). Animates the page back to its original position.
  void _handleDragCancel(BuildContext context) {
    if (_isPopping || _isAnimating) {
      _isDragging = false;
      _currentDragDirection = 0;
      return;
    }

    final controller = _controller;
    if (controller == null || !_isDragging) return;

    _cancelPop(context, controller);
    _currentDragDirection = 0;
  }

  /// Performs the pop operation with animation.
  ///
  /// Animates the controller to 0 (fully dismissed) and then pops the route.
  /// The animation duration is proportional to the remaining distance.
  ///
  /// This method is protected against multiple simultaneous calls.
  void _performPop(BuildContext context, AnimationController controller) {
    // Prevent multiple simultaneous pop operations
    if (_isPopping || _isAnimating) return;

    _isPopping = true;
    _isAnimating = true;
    _isDragging = false;

    final navigator = Navigator.of(context);

    // Calculate proportional duration based on remaining distance
    final duration = Duration(
      milliseconds: (widget.transitionDuration.inMilliseconds *
              controller.value)
          .round()
          .clamp(
            widget.transitionDuration.inMilliseconds ~/ 1.5,
            widget.transitionDuration.inMilliseconds,
          ),
    );

    // Notify navigator that the user gesture has completedD

    //! I noticed that when closing the page with a swipe, the Hero animation flickers occasionally, and I wasn’t able to fix it.
    //! It’s possible that navigator.didStopUserGesture() and Navigator.of(context).didStartUserGesture() are being used incorrectly here.
    navigator.didStopUserGesture();

    // Animate to fully dismissed state with easeInOut curve
    // to avoid visual jump from drag to animation
    controller
        .animateTo(0.0, duration: duration, curve: Curves.easeInOut)
        .whenComplete(() {
          if (mounted) {
            navigator.pop();
          }
        });
  }

  /// Cancels the pop operation and animates back to the original position.
  ///
  /// Animates the controller back to 1.0 (fully visible). The animation
  /// duration is proportional to the remaining distance.
  void _cancelPop(BuildContext context, AnimationController controller) {
    if (_isPopping || _isAnimating) return;

    _isAnimating = true;
    _isDragging = false;

    // Calculate proportional duration based on remaining distance
    final duration = Duration(
      milliseconds: (widget.transitionDuration.inMilliseconds *
              (1.0 - controller.value))
          .round()
          .clamp(
            widget.transitionDuration.inMilliseconds ~/ 2,
            widget.transitionDuration.inMilliseconds,
          ),
    );

    // Animate back to fully visible state with easeInOut curve
    // to avoid visual jump from drag to animation
    controller
        .animateTo(1.0, duration: duration, curve: Curves.easeInOut)
        .whenComplete(() {
          _isAnimating = false;

          if (!mounted) return;

          // Notify navigator that the user gesture has completed
          Navigator.of(context).didStopUserGesture();
        });
  }
}

