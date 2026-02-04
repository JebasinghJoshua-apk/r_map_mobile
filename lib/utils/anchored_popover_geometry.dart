import 'package:flutter/material.dart';

class AnchoredPopoverGeometry {
  const AnchoredPopoverGeometry({
    required this.popupTop,
    required this.popupLeft,
    required this.popupWidth,
    required this.arrowLeft,
  });

  final double popupTop;
  final double popupLeft;
  final double popupWidth;
  final double arrowLeft;

  static AnchoredPopoverGeometry compute({
    required MediaQueryData media,
    required Rect popupAnchorRect,
    required Rect arrowAnchorRect,
    required double horizontalPadding,
    required double popupWidth,
    required double arrowWidth,
    required double popupGap,
    required double popupOverlapIntoAnchor,
    double minTopGap = 4,
    double arrowSidePadding = 12,
  }) {
    final size = media.size;

    final safeTop = media.padding.top;
    final popupTopRaw =
        popupAnchorRect.bottom + popupGap - popupOverlapIntoAnchor;
    final popupTop =
        popupTopRaw < safeTop + minTopGap ? safeTop + minTopGap : popupTopRaw;

    final anchorCenterX = arrowAnchorRect.left + (arrowAnchorRect.width / 2);

    final popupLeftRaw = anchorCenterX - (popupWidth / 2);
    final popupLeftMax = size.width - horizontalPadding - popupWidth;
    final popupLeft = popupLeftRaw < horizontalPadding
        ? horizontalPadding
        : (popupLeftRaw > popupLeftMax ? popupLeftMax : popupLeftRaw);

    final arrowLeftMin = popupLeft + arrowSidePadding;
    final arrowLeftMax = popupLeft + popupWidth - arrowSidePadding - arrowWidth;
    final arrowLeftRaw = anchorCenterX - (arrowWidth / 2);
    final arrowLeft = arrowLeftRaw < arrowLeftMin
        ? arrowLeftMin
        : (arrowLeftRaw > arrowLeftMax ? arrowLeftMax : arrowLeftRaw);

    return AnchoredPopoverGeometry(
      popupTop: popupTop,
      popupLeft: popupLeft,
      popupWidth: popupWidth,
      arrowLeft: arrowLeft,
    );
  }

  static AnchoredPopoverGeometry computeFullWidth({
    required MediaQueryData media,
    required Rect popupAnchorRect,
    required Rect arrowAnchorRect,
    required double horizontalPadding,
    required double arrowWidth,
    required double popupGap,
    required double popupOverlapIntoAnchor,
    double minTopGap = 4,
    double arrowSidePadding = 12,
  }) {
    final size = media.size;
    final popupWidth = size.width - (horizontalPadding * 2);
    final popupLeft = horizontalPadding;

    final safeTop = media.padding.top;
    final popupTopRaw =
        popupAnchorRect.bottom + popupGap - popupOverlapIntoAnchor;
    final popupTop =
        popupTopRaw < safeTop + minTopGap ? safeTop + minTopGap : popupTopRaw;

    final arrowAnchorCenterX =
        arrowAnchorRect.left + (arrowAnchorRect.width / 2);
    final arrowLeftRaw = arrowAnchorCenterX - (arrowWidth / 2);
    final arrowLeftMin = popupLeft + arrowSidePadding;
    final arrowLeftMax = popupLeft + popupWidth - arrowSidePadding - arrowWidth;
    final arrowLeft = arrowLeftRaw < arrowLeftMin
        ? arrowLeftMin
        : (arrowLeftRaw > arrowLeftMax ? arrowLeftMax : arrowLeftRaw);

    return AnchoredPopoverGeometry(
      popupTop: popupTop,
      popupLeft: popupLeft,
      popupWidth: popupWidth,
      arrowLeft: arrowLeft,
    );
  }
}
