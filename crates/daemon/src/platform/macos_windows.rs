use core_graphics::display::CGDisplay;
use oc_apprentice_common::event::{DisplayInfo, WindowInfo};

/// Get all active display information (multi-monitor topology).
pub fn get_display_topology() -> Vec<DisplayInfo> {
    let display_ids = CGDisplay::active_displays().unwrap_or_default();

    display_ids
        .iter()
        .map(|&id| {
            let display = CGDisplay::new(id);
            let bounds = display.bounds();
            let scale = if display.pixels_wide() > 0 && bounds.size.width > 0.0 {
                display.pixels_wide() as f64 / bounds.size.width
            } else {
                1.0
            };

            DisplayInfo {
                display_id: id.to_string(),
                bounds_global_px: [
                    bounds.origin.x as i32,
                    bounds.origin.y as i32,
                    bounds.size.width as i32,
                    bounds.size.height as i32,
                ],
                scale_factor: scale,
                orientation: display.rotation() as u32,
            }
        })
        .collect()
}

/// Get the focused (frontmost) window info.
/// Returns None if no window is focused or in headless environments.
pub fn get_focused_window() -> Option<WindowInfo> {
    // Full implementation requires NSWorkspace + CGWindowList
    // For now, return None as a safe default
    None
}
