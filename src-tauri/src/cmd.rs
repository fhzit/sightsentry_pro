use serde::{Deserialize, Serialize};
use std::sync::Mutex;

#[cfg(not(target_os = "android"))]
use tauri::{AppHandle, Manager, State};
#[cfg(not(target_os = "android"))]
use tauri_plugin_serial::{SerialPort, SerialPortInfo};
#[cfg(not(target_os = "android"))]
use tauri_plugin_bluetooth::BluetoothManager;

pub struct SerialState {
    pub port: Mutex<Option<Box<dyn SerialPort>>>,
}

#[cfg(target_os = "android")]
pub struct SerialState {
    pub port: Mutex<Option<()>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SerialPortInfoDto {
    pub name: String,
    pub port_type: String,
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn get_serial_ports() -> Result<Vec<SerialPortInfoDto>, String> {
    log::info!("Getting serial ports...");
    let ports = tauri_plugin_serial::available_ports().map_err(|e| e.to_string())?;
    Ok(ports
        .into_iter()
        .map(|p| SerialPortInfoDto {
            name: p.port_name,
            port_type: format!("{:?}", p.port_type),
        })
        .collect())
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn connect_serial(
    app: AppHandle,
    path: String,
    baud_rate: u32,
) -> Result<(), String> {
    log::info!("Connecting to serial port: {} at {}", path, baud_rate);
    let serial = tauri_plugin_serial::open_port(&path, baud_rate).map_err(|e| e.to_string())?;
    app.state::<SerialState>().port.lock().unwrap().replace(serial);
    Ok(())
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn disconnect_serial(state: State<'_, SerialState>) -> Result<(), String> {
    log::info!("Disconnecting serial port");
    let mut port = state.port.lock().unwrap();
    if let Some(serial) = port.take() {
        serial.close().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn read_serial_data(state: State<'_, SerialState>) -> Result<String, String> {
    let port = state.port.lock().unwrap();
    if let Some(serial) = port.as_ref() {
        let mut buffer = [0; 1024];
        let size = serial.read(&mut buffer).map_err(|e| e.to_string())?;
        Ok(String::from_utf8_lossy(&buffer[..size]).to_string())
    } else {
        Err("No serial port connected".into())
    }
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn write_serial_data(state: State<'_, SerialState>, data: String) -> Result<(), String> {
    let port = state.port.lock().unwrap();
    if let Some(serial) = port.as_ref() {
        serial.write(data.as_bytes()).map_err(|e| e.to_string())?;
        Ok(())
    } else {
        Err("No serial port connected".into())
    }
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn scan_bluetooth() -> Result<Vec<String>, String> {
    log::info!("Scanning for Bluetooth devices...");
    let manager = BluetoothManager::new().map_err(|e| e.to_string())?;
    let devices = manager.scan().await.map_err(|e| e.to_string())?;
    Ok(devices.into_iter().map(|d| d.name).collect())
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn connect_bluetooth(device_name: String) -> Result<(), String> {
    log::info!("Connecting to Bluetooth device: {}", device_name);
    let manager = BluetoothManager::new().map_err(|e| e.to_string())?;
    manager.connect(&device_name).await.map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(not(target_os = "android"))]
#[tauri::command]
pub async fn disconnect_bluetooth(device_name: String) -> Result<(), String> {
    log::info!("Disconnecting Bluetooth device: {}", device_name);
    let manager = BluetoothManager::new().map_err(|e| e.to_string())?;
    manager.disconnect(&device_name).await.map_err(|e| e.to_string())?;
    Ok(())
}
