#[cfg(target_os = "macos")]
pub mod macos;
#[cfg(target_os = "macos")]
pub mod macos_accessibility;
#[cfg(target_os = "macos")]
pub mod macos_windows;
#[cfg(target_os = "macos")]
pub mod macos_power;

#[cfg(target_os = "macos")]
pub use macos::IdleDetector;

#[cfg(target_os = "macos")]
pub mod accessibility {
    pub use super::macos_accessibility::*;
}

#[cfg(target_os = "macos")]
pub mod window_capture {
    pub use super::macos_windows::*;
}

#[cfg(target_os = "macos")]
pub mod power {
    pub use super::macos_power::*;
}
