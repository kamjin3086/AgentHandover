use anyhow::{bail, Result};
use std::path::PathBuf;

fn sops_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    // Default OpenClaw workspace path
    PathBuf::from(home).join(".openclaw/workspace/memory/apprentice/sops")
}

pub fn list() -> Result<()> {
    let dir = sops_dir();
    if !dir.exists() {
        println!("No SOPs directory found at: {}", dir.display());
        println!("SOPs will be generated once enough workflow patterns are detected.");
        return Ok(());
    }

    let mut sop_files: Vec<_> = std::fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.path().extension().map_or(false, |ext| ext == "md")
                && e.file_name().to_string_lossy().starts_with("sop.")
        })
        .collect();

    if sop_files.is_empty() {
        println!("No SOPs generated yet.");
        println!("SOPs appear once the system detects repeated workflow patterns.");
        return Ok(());
    }

    sop_files.sort_by_key(|e| e.file_name());

    println!("Generated SOPs ({}):", sop_files.len());
    println!("{}", "-".repeat(60));
    for entry in &sop_files {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        // Extract slug from "sop.<slug>.md"
        let slug = name_str
            .strip_prefix("sop.")
            .and_then(|s| s.strip_suffix(".md"))
            .unwrap_or(&name_str);

        // Try to read first heading
        let title = std::fs::read_to_string(entry.path())
            .ok()
            .and_then(|content| {
                content
                    .lines()
                    .find(|l| l.starts_with("# "))
                    .map(|l| l[2..].trim().to_string())
            })
            .unwrap_or_else(|| slug.replace('-', " "));

        let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
        println!("  {} -- {} ({} bytes)", slug, title, size);
    }

    Ok(())
}

pub fn show(slug: &str) -> Result<()> {
    let file_path = sops_dir().join(format!("sop.{}.md", slug));
    if !file_path.exists() {
        bail!("SOP '{}' not found at: {}", slug, file_path.display());
    }
    let content = std::fs::read_to_string(&file_path)?;
    println!("{}", content);
    Ok(())
}

pub fn dir() -> Result<()> {
    println!("{}", sops_dir().display());
    Ok(())
}
