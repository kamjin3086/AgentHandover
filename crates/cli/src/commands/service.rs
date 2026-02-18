use anyhow::{bail, Result};
use std::process::Command;

const DAEMON_LABEL: &str = "com.openmimic.daemon";
const WORKER_LABEL: &str = "com.openmimic.worker";

fn launch_agents_dir() -> std::path::PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    std::path::PathBuf::from(home).join("Library/LaunchAgents")
}

fn plist_path(label: &str) -> String {
    launch_agents_dir()
        .join(format!("{}.plist", label))
        .display()
        .to_string()
}

fn launchctl(args: &[&str]) -> Result<()> {
    let output = Command::new("launchctl").args(args).output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.trim().is_empty() {
            eprintln!("  launchctl: {}", stderr.trim());
        }
    }
    Ok(())
}

pub fn start(service: &str) -> Result<()> {
    match service {
        "daemon" => {
            println!("Starting daemon...");
            launchctl(&["load", "-w", &plist_path(DAEMON_LABEL)])?;
            println!("  Daemon started.");
        }
        "worker" => {
            println!("Starting worker...");
            launchctl(&["load", "-w", &plist_path(WORKER_LABEL)])?;
            println!("  Worker started.");
        }
        "all" => {
            println!("Starting all services...");
            launchctl(&["load", "-w", &plist_path(DAEMON_LABEL)])?;
            launchctl(&["load", "-w", &plist_path(WORKER_LABEL)])?;
            println!("  All services started.");
        }
        _ => bail!(
            "Unknown service: {}. Use 'daemon', 'worker', or 'all'.",
            service
        ),
    }
    Ok(())
}

pub fn stop(service: &str) -> Result<()> {
    match service {
        "daemon" => {
            println!("Stopping daemon...");
            launchctl(&["unload", &plist_path(DAEMON_LABEL)])?;
            println!("  Daemon stopped.");
        }
        "worker" => {
            println!("Stopping worker...");
            launchctl(&["unload", &plist_path(WORKER_LABEL)])?;
            println!("  Worker stopped.");
        }
        "all" => {
            println!("Stopping all services...");
            launchctl(&["unload", &plist_path(DAEMON_LABEL)])?;
            launchctl(&["unload", &plist_path(WORKER_LABEL)])?;
            println!("  All services stopped.");
        }
        _ => bail!(
            "Unknown service: {}. Use 'daemon', 'worker', or 'all'.",
            service
        ),
    }
    Ok(())
}

pub fn restart(service: &str) -> Result<()> {
    stop(service)?;
    std::thread::sleep(std::time::Duration::from_secs(1));
    start(service)?;
    Ok(())
}
