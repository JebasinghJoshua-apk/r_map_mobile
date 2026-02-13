part of '../home_map_screen.dart';

extension _HomeMapControls on _HomeMapScreenState {
  void _toggleSatelliteMode() {
    _updateState(() {
      _mapType = _mapType == MapType.hybrid ? MapType.normal : MapType.hybrid;
      // Lock to user selection for this session (prevents zoom-based auto-switch).
      _userSelectedMapType = true;
    });
  }

  Future<void> _zoomIn() async {
    await _animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    await _animateCamera(CameraUpdate.zoomOut());
  }

  Widget _mapZoomControl() {
    const radius = 8.0;
    const size = 36.0;
    const borderColor = Color(0xFFE2E8F0);

    Widget segment({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      required BorderRadius borderRadius,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: 18,
                color: const Color(0xFF1F2937),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              icon: Icons.add,
              tooltip: 'Zoom in',
              onPressed: () => unawaited(_zoomIn()),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: borderColor),
            segment(
              icon: Icons.remove,
              tooltip: 'Zoom out',
              onPressed: () => unawaited(_zoomOut()),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(radius),
                bottomRight: Radius.circular(radius),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool highlight = false,
  }) {
    const radius = 8.0;
    const size = 36.0;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Material(
              color: Colors.white,
              elevation: 4,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(radius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: Icon(
                  icon,
                  size: 18,
                  color: const Color(0xFF1F2937),
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: highlight ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: const Color(0xFF14B8A6),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x3314B8A6),
                        blurRadius: 14,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
