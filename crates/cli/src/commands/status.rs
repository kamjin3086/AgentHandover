use anyhow::Result;
use colored::Colorize;
use oc_apprentice_common::pid;
use oc_apprentice_common::status;

pub fn run() -> Result<()> {
    println!("{}", "OpenMimic Status".bold());
    println!("{}", "=".repeat(50));
    println!();

    // Daemon status
    print_service_status("Daemon", "daemon-status.json", "daemon");
    println!();

    // Worker status
    print_service_status("Worker", "worker-status.json", "worker");

    Ok(())
}

fn print_service_status(name: &str, status_file: &str, pid_name: &str) {
    let pid_alive = pid::check_pid_file(pid_name);

    match status::read_status_file::<serde_json::Value>(status_file) {
        Ok(value) => {
            let status_icon = if pid_alive.is_some() {
                "●".green()
            } else {
                "●".red()
            };

            println!(
                "  {} {} {}",
                status_icon,
                name.bold(),
                if pid_alive.is_some() {
                    "(running)".green()
                } else {
                    "(not responding)".red()
                }
            );

            if let Some(pid) = value.get("pid").and_then(|v| v.as_u64()) {
                println!("    PID:       {}", pid);
            }
            if let Some(version) = value.get("version").and_then(|v| v.as_str()) {
                println!("    Version:   {}", version);
            }
            if let Some(heartbeat) = value.get("heartbeat").and_then(|v| v.as_str()) {
                println!("    Heartbeat: {}", heartbeat);
            }

            // Daemon-specific fields
            if let Some(events) = value.get("events_today").and_then(|v| v.as_u64()) {
                println!("    Events:    {}", events);
            }
            if let Some(perms) = value.get("permissions_ok").and_then(|v| v.as_bool()) {
                let perms_str = if perms {
                    "OK".green()
                } else {
                    "MISSING".red()
                };
                println!("    Perms:     {}", perms_str);
            }

            // Worker-specific fields
            if let Some(sops) = value.get("sops_generated").and_then(|v| v.as_u64()) {
                println!("    SOPs:      {}", sops);
            }
            if let Some(errors) = value.get("consecutive_errors").and_then(|v| v.as_u64()) {
                if errors > 0 {
                    println!("    Errors:    {}", format!("{}", errors).red());
                }
            }
        }
        Err(_) => {
            let status_icon = "○".dimmed();
            println!(
                "  {} {} {}",
                status_icon,
                name.bold(),
                "(not running)".dimmed()
            );
            if let Some(pid) = pid_alive {
                println!("    PID {} is alive but no status file found", pid);
            }
        }
    }
}
