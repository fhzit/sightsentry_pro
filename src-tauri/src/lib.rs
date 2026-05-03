use std::sync::Mutex;

mod cmd;
use cmd::SerialState;

#[cfg(not(target_os = "android"))]
pub fn run() {
    use tauri::Manager;

    env_logger::init();
    log::info!("Starting SightSentry Pro...");

    tauri::Builder::default()
        .plugin(tauri_plugin_serial::init())
        .plugin(tauri_plugin_bluetooth::init())
        .manage(SerialState {
            port: Mutex::new(None),
        })
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

#[cfg(target_os = "android")]
use std::sync::OnceLock;

#[cfg(target_os = "android")]
static STATE: OnceLock<SerialState> = OnceLock::new();

#[cfg(target_os = "android")]
fn get_state() -> &'static SerialState {
    STATE.get_or_init(|| SerialState {
        port: Mutex::new(None),
    })
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn Java_com_sightsentry_pro_MainActivity_handleNativeMessage(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    message: jni::objects::JString,
) -> jni::sys::jstring {
    let msg: String = env
        .get_string(&message)
        .map(|s| s.into())
        .unwrap_or_default();

    log::info!("Native message received: {}", msg);

    let response = match serde_json::from_str::<serde_json::Value>(&msg) {
        Ok(cmd) => {
            let action = cmd["action"].as_str().unwrap_or("");
            match action {
                "get_serial_ports" => {
                    serde_json::json!({"result": "not_implemented_on_android"})
                }
                "connect_serial" => {
                    serde_json::json!({"result": "not_implemented_on_android"})
                }
                "get_native_info" => {
                    serde_json::json!({"platform": "android", "native": true})
                }
                _ => {
                    serde_json::json!({"error": format!("Unknown action: {}", action)})
                }
            }
        }
        Err(e) => {
            serde_json::json!({"error": format!("Parse error: {}", e)})
        }
    };

    let response_str = response.to_string();
    env.new_string(&response_str)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn JNI_OnLoad(
    _vm: jni::JavaVM,
    _: *mut std::ffi::c_void,
) -> jni::sys::jint {
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Info)
            .with_tag("SightSentry"),
    );
    log::info!("SightSentry native library loaded");
    jni::sys::JNI_VERSION_1_6
}
