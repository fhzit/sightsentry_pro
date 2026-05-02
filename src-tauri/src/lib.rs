use tauri::Manager;
use std::sync::Mutex;

mod cmd;
use cmd::SerialState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    env_logger::init();
    log::info!("Starting SightSentry Pro...");

    tauri::Builder::default()
        .plugin(tauri_plugin_serial::init())
        .plugin(tauri_plugin_bluetooth::init())
        .manage(SerialState { port: Mutex::new(None) })
        .invoke_handler(tauri::generate_handler![
            cmd::get_serial_ports,
            cmd::connect_serial,
            cmd::disconnect_serial,
            cmd::read_serial_data,
            cmd::write_serial_data,
            cmd::scan_bluetooth,
            cmd::connect_bluetooth,
            cmd::disconnect_bluetooth
        ])
        .setup(|app| {
            log::info!("Application setup complete");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
