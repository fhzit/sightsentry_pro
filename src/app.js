// Tauri modules are loaded dynamically when running inside Tauri

const OUI_DATABASE = {
    "00:1A:2B": "Intel", "00:1E:8C": "Apple", "00:21:CC": "Apple",
    "00:23:12": "Apple", "00:23:DF": "Apple", "00:26:08": "Apple",
    "00:26:BB": "Apple", "00:30:65": "Cisco", "00:40:96": "Cisco",
    "18:00:20": "Apple", "28:63:36": "Apple", "30:23:03": "Apple",
    "34:15:9E": "Apple", "38:2C:4A": "Apple", "40:B0:34": "Apple",
    "44:39:C4": "Apple", "58:55:CA": "Apple", "5C:AA:FD": "Apple",
    "60:14:5C": "Samsung", "64:B9:E8": "Apple", "68:5B:35": "Apple",
    "70:56:81": "Apple", "78:CA:39": "Apple", "7C:6D:62": "Apple",
    "80:2A:A8": "Apple", "84:38:35": "Apple", "88:1F:A1": "Samsung",
    "90:27:E4": "Apple", "94:10:3B": "Samsung", "98:01:A7": "Apple",
    "A0:88:B4": "Apple", "A4:5E:60": "Apple", "AC:DE:48": "Apple",
    "B4:99:4C": "Apple", "BC:17:BB": "Samsung", "C0:EE:FB": "Apple",
    "C4:2C:03": "Apple", "C8:2A:14": "Apple", "D0:23:DB": "Apple",
    "D4:9A:20": "Apple", "DC:4A:3E": "Apple", "E0:98:06": "Apple",
    "E4:95:6E": "Apple", "EC:35:86": "Apple", "F0:18:98": "Apple",
    "F4:5C:89": "Apple"
};

let settings = {
    distanceParam: 2.5,
    rssiAt1m: -59,
    timeoutSec: 30,
    refreshRate: 1000,
    showDebug: false,
    enableDeviceFilter: true
};

let devices = new Map();
let connectedNodes = new Set();
let isDarkMode = false;
let currentFilter = 'all';
let serialReader = null;
let serialPort = null;
let serialPortList = []; // store available SerialPort objects from navigator.serial.getPorts()
let animationId = null;
let updateTimer = null;
let bleConnections = new Map(); // support multiple BLE nodes on desktop as well
let bleReconnectTimer = null;
let bleHeartbeatTimer = null;
let duplicateWarnTime = 0;

document.addEventListener('DOMContentLoaded', initApp);

async function initApp() {
    loadSettings();
    setupEventListeners();
    updateDeviceList();
    window.addEventListener('beforeunload', cleanup);
    
    logDebug('SightSentry Pro initialized');
}

function setupEventListeners() {
    document.getElementById('serialBtn').addEventListener('click', connectSerial);
    document.getElementById('bleBtn').addEventListener('click', connectBLE);
    document.getElementById('disconnectBtn').addEventListener('click', disconnectAll);
    document.getElementById('refreshPortsBtn').addEventListener('click', refreshSerialPorts);
    document.getElementById('themeToggle').addEventListener('click', toggleTheme);
    document.getElementById('settingsBtn').addEventListener('click', openSettings);
    document.querySelector('.close').addEventListener('click', closeSettings);
    document.getElementById('saveSettings').addEventListener('click', saveSettings);
    document.getElementById('resetSettings').addEventListener('click', resetSettings);
    document.getElementById('clearLog').addEventListener('click', clearDebugLog);
    
    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            currentFilter = e.target.dataset.filter;
            renderDeviceList();
        });
    });
}

async function setupTauriWindowControls() {
    try {
        const { getCurrentWindow } = await import('@tauri-apps/api/window');
        const appWindow = getCurrentWindow();
        document.getElementById('minimizeBtn').addEventListener('click', () => appWindow.minimize());
        document.getElementById('maximizeBtn').addEventListener('click', async () => {
            const isMaximized = await appWindow.isMaximized();
            if (isMaximized) {
                appWindow.unmaximize();
            } else {
                appWindow.maximize();
            }
        });
        document.getElementById('closeBtn').addEventListener('click', () => appWindow.close());
    } catch (e) {
        console.log('Window controls not available in browser');
    }
}

async function refreshSerialPorts() {
    try {
        const ports = await navigator.serial.getPorts();
        const select = document.getElementById('serialPortSelect');
        serialPortList = ports;
        select.innerHTML = '<option value="">-- 选择串口 --</option>';
        ports.forEach((port, idx) => {
            const info = port.getInfo();
            const vid = info.usbVendorId ? info.usbVendorId : '??';
            const pid = info.usbProductId ? info.usbProductId : '??';
            const label = `VID:${vid} PID:${pid}`;
            select.innerHTML += `<option value="${idx}">${label}</option>`;
        });
        logDebug(`Found ${ports.length} serial ports`);
    } catch (e) {
        logDebug('Error refreshing ports: ' + e.message);
    }
}

async function connectSerial() {
    console.log('connectSerial start');
    try {
        // refresh port list to ensure indices are up-to-date
        await refreshSerialPorts();
        const selectedPort = document.getElementById('serialPortSelect').value;
        document.getElementById('connectionStatus').textContent = '连接中...';
        logDebug('Begin serial connection');

        // Helper for retry
        const sleep = (ms) => new Promise(r => setTimeout(r, ms));
        let openError = null;
        // Determine initial port source
        if (selectedPort) {
            const idx = parseInt(selectedPort);
            if (!isNaN(idx) && serialPortList[idx]) {
                serialPort = serialPortList[idx];
            } else {
                try {
                    serialPort = await navigator.serial.requestPort();
                } catch (e) {
                    console.error('requestPort fallback failed', e);
                }
            }
        } else {
            try {
                serialPort = await navigator.serial.requestPort();
            } catch (e) {
                console.error('requestPort cancelled or failed', e);
            }
        }

        // Try opening with a few retries because device may be temporarily busy after reboot
        const maxAttempts = 3;
        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                if (!serialPort) throw new Error('No serial port selected');
                await serialPort.open({ baudRate: 115200 });
                openError = null;
                break;
            } catch (err) {
                openError = err;
                console.warn(`Serial open attempt ${attempt} failed:`, err);
                // On first failure, try refreshing port list and remapping selected index
                if (attempt < maxAttempts) {
                    await sleep(600);
                    await refreshSerialPorts();
                    if (selectedPort) {
                        const idx = parseInt(selectedPort);
                        if (!isNaN(idx) && serialPortList[idx]) serialPort = serialPortList[idx];
                    }
                }
            }
        }

        if (openError) {
            console.error('Failed to open serial port after retries:', openError);
            document.getElementById('connectionStatus').textContent = '未连接';
            alert('无法打开串口：' + (openError.message || openError) + '\n可能原因：设备刚重启尚未准备好，或被其他程序占用，或浏览器权限未授予。请尝试：\n- 重新插拔设备并刷新串口列表；\n- 关闭可能占用串口的程序（串口监视、串口驱动工具等）；\n- 在浏览器地址栏允许串口访问；\n- 使用浏览器的隐私/权限设置检查串口权限。');
            logDebug('Serial open error: ' + (openError.message || openError));
            return;
        }

        if (!serialPort.readable) {
            throw new Error('串口不可读');
        }

        serialReader = serialPort.readable.getReader();

        document.getElementById('connectionStatus').textContent = '已连接(USB)';
        document.getElementById('disconnectBtn').style.display = 'inline-block';
        document.getElementById('serialBtn').disabled = true;
        document.getElementById('bleBtn').disabled = true;

        logDebug('Serial connected');
        readSerialLoop();
    } catch (e) {
        console.error(e);
        document.getElementById('connectionStatus').textContent = '未连接';
        logDebug('Serial error: ' + (e.message || e));
    }
}

async function readSerialLoop() {
    let buffer = '';
    const decoder = new TextDecoder();
    try {
        while (true) {
            const { value, done } = await serialReader.read();
            if (done) break;
            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split('\n');
            buffer = lines.pop();
            for (const line of lines) {
                processDataLine(line.trim());
            }
        }
    } catch (e) {
        console.error(e);
        logDebug('Serial read error: ' + (e.message || e));
    } finally {
        if (serialReader) {
            await serialReader.releaseLock();
            serialReader = null;
        }
    }
}

async function connectBLE() {
    try {
        const device = await navigator.bluetooth.requestDevice({
            filters: [{ namePrefix: 'SightSentry' }],
            optionalServices: ['6e400001-b5a3-f393-e0a9-e50e24dcca9e']
        });

        if (!device) {
            logDebug('No device selected');
            document.getElementById('connectionStatus').textContent = '未连接';
            return;
        }

        document.getElementById('connectionStatus').textContent = '连接中...';
        logDebug('Attempting BLE connect...');

        // Attempt to connect + get service/characteristic with retries because some devices
        // briefly drop GATT or take time to be ready.
        const sleep = (ms) => new Promise(r => setTimeout(r, ms));
        let server = null, service = null, characteristic = null;
        const maxAttempts = 3;
        let lastErr = null;
        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                server = await device.gatt.connect();
                service = await server.getPrimaryService('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
                characteristic = await service.getCharacteristic('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
                lastErr = null;
                break;
            } catch (err) {
                lastErr = err;
                console.warn(`Attempt ${attempt} failed to get service/characteristic:`, err);
                if (attempt < maxAttempts) await sleep(500);
            }
        }
        if (lastErr) {
            throw lastErr;
        }

        // Setup connection placeholder and listener references so we can remove them later
        const onValueChanged = (event) => {
            try {
                const text = new TextDecoder().decode(event.target.value);
                const conn = bleConnections.get(device.id);
                if (!conn) return;
                conn.lastSeen = Date.now();
                conn.buffer = (conn.buffer || '') + text;
                const lines = conn.buffer.split('\n');
                conn.buffer = lines.pop();
                for (const rawLine of lines) {
                    const line = rawLine.trim();
                    if (!line) continue;
                    processDataLine(line, device.id);
                }
                renderBleNodes();
            } catch (err) {
                console.error('BLE decode error', err);
            }
        };

        const onGattDisconnected = () => {
            console.warn('BLE device disconnected:', device.id, device.name);
            const conn = bleConnections.get(device.id);
            if (conn) {
                // mark server as disconnected; keep entry for UI and possible reconnect
                conn.server = null;
                conn.characteristic = null;
            }
            renderBleNodes();
        };

        // store connection info
        bleConnections.set(device.id, { device, server, characteristic, lastSeen: Date.now(), autoReconnect: false, buffer: '', listener: onValueChanged, gattHandler: onGattDisconnected });

        characteristic.addEventListener('characteristicvaluechanged', onValueChanged);
        device.addEventListener('gattserverdisconnected', onGattDisconnected);

        await characteristic.startNotifications();

        renderBleNodes();
        startBleHeartbeatLoop();

        logDebug('BLE connected to ' + (device.name || device.id));
    } catch (e) {
        console.error(e);
        logDebug('BLE error: ' + (e.message || e));
        alert('BLE 连接失败：' + (e.message || e));
    }
}

function renderBleNodes() {
    const container = document.getElementById('bleNodes');
    if (!container) return;
    container.innerHTML = '';
    bleConnections.forEach((conn, id) => {
        const div = document.createElement('div');
        div.className = 'ble-node-item';
        const name = conn.device.name || id;
        const last = conn.lastSeen ? (() => {
            const delta = Date.now() - conn.lastSeen;
            if (delta < 1500) return '刚刚';
            return `${Math.round(delta/1000)}s前`;
        })() : '--';
        const arChecked = conn.autoReconnect ? 'checked' : '';
        div.innerHTML = `<span class="ble-name">${name}</span> <span class="ble-last">活跃:${last}</span> <label class="ar"><input type="checkbox" class="node-auto-reconnect" data-id="${id}" ${arChecked}>自动重连</label> <button class="ble-reconnect" data-id="${id}">重连</button> <button class="ble-disconnect" data-id="${id}">断开</button>`;
        container.appendChild(div);
    });
    container.querySelectorAll('.ble-disconnect').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const id = e.target.dataset.id;
            disconnectBleNode(id);
        });
    });
    container.querySelectorAll('.ble-reconnect').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const id = e.target.dataset.id;
            await tryReconnectNode(id);
        });
    });
    container.querySelectorAll('.node-auto-reconnect').forEach(cb => {
        cb.addEventListener('change', (e) => {
            const id = e.target.dataset.id;
            const conn = bleConnections.get(id);
            if (conn) conn.autoReconnect = e.target.checked;
        });
    });
    const status = document.getElementById('connectionStatus');
    if (bleConnections.size > 0) {
        status.textContent = `已连接(BLE:${bleConnections.size})`;
    } else {
        status.textContent = '未连接';
    }
}

function startBleHeartbeatLoop() {
    if (bleHeartbeatTimer) return;
    bleHeartbeatTimer = setInterval(() => {
        // re-render to update heartbeat labels
        if (bleConnections.size === 0) {
            stopBleHeartbeatLoop();
            return;
        }
        renderBleNodes();
    }, 1000);
}

function stopBleHeartbeatLoop() {
    if (bleHeartbeatTimer) {
        clearInterval(bleHeartbeatTimer);
        bleHeartbeatTimer = null;
    }
}

async function disconnectBleNode(id) {
    const conn = bleConnections.get(id);
    if (!conn) return;
    try {
        if (conn.characteristic) {
            try { await conn.characteristic.stopNotifications(); } catch (e) {}
        }
        if (conn.server && conn.server.connected) {
            conn.server.disconnect();
        }
    } catch (e) {
        console.warn('Error disconnecting', e);
    }
    bleConnections.delete(id);
    renderBleNodes();
    if (bleConnections.size === 0) stopBleHeartbeatLoop();
}

async function disconnectAllBle() {
    const ids = Array.from(bleConnections.keys());
    for (const id of ids) {
        await disconnectBleNode(id);
    }
}

async function tryReconnectNode(id) {
    const conn = bleConnections.get(id);
    if (!conn) return;
    try {
        if (!conn.server || !conn.server.connected) {
            const sleep = (ms) => new Promise(r => setTimeout(r, ms));
            let server = null, service = null, characteristic = null;
            let lastErr = null;
            for (let attempt = 1; attempt <= 3; attempt++) {
                try {
                    server = await conn.device.gatt.connect();
                    service = await server.getPrimaryService('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
                    characteristic = await service.getCharacteristic('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
                    lastErr = null;
                    break;
                } catch (err) {
                    lastErr = err;
                    console.warn(`Attempt ${attempt} failed to get service/characteristic:`, err);
                    if (attempt < 3) await sleep(500);
                }
            }
            if (lastErr) {
                throw lastErr;
            }

            const onValueChanged = (event) => {
                try {
                    const text = new TextDecoder().decode(event.target.value);
                    const c = bleConnections.get(id);
                    if (c) c.lastSeen = Date.now();
                    // append and parse newline-terminated lines
                    c.buffer = (c.buffer || '') + text;
                    const lines = c.buffer.split('\n');
                    c.buffer = lines.pop();
                    for (const raw of lines) if (raw && raw.trim()) processDataLine(raw.trim(), id);
                    renderBleNodes();
                } catch (err) { console.error('BLE reconnect decode error', err); }
            };

            const onGattDisconnected = () => {
                console.warn('BLE device disconnected (reconnect path):', id, conn.device.name);
                const c = bleConnections.get(id);
                if (c) { c.server = null; c.characteristic = null; }
                renderBleNodes();
            };

            // remove old listeners if any
            try {
                if (conn.characteristic && conn.listener) conn.characteristic.removeEventListener('characteristicvaluechanged', conn.listener);
                if (conn.device && conn.gattHandler) conn.device.removeEventListener('gattserverdisconnected', conn.gattHandler);
            } catch (e) {}

            characteristic.addEventListener('characteristicvaluechanged', onValueChanged);
            conn.device.addEventListener('gattserverdisconnected', onGattDisconnected);

            await characteristic.startNotifications();
            bleConnections.set(id, { device: conn.device, server, characteristic, lastSeen: Date.now(), autoReconnect: conn.autoReconnect, buffer: '', listener: onValueChanged, gattHandler: onGattDisconnected });
            renderBleNodes();
            startBleHeartbeatLoop();
        }
    } catch (e) {
        console.warn('Reconnect failed', e);
    }
}

function startBleReconnectLoop() {
    if (bleReconnectTimer) return;
    bleReconnectTimer = setInterval(async () => {
        const globalAuto = document.getElementById('autoReconnect') ? document.getElementById('autoReconnect').checked : false;
        bleConnections.forEach(async (conn, id) => {
            if ((!conn.server || !conn.server.connected) && (globalAuto || conn.autoReconnect)) {
                await tryReconnectNode(id);
            }
        });
    }, 5000);
}

document.addEventListener('DOMContentLoaded', () => {
    const auto = document.getElementById('autoReconnect');
    if (auto) {
        auto.addEventListener('change', () => startBleReconnectLoop());
    }
    startBleReconnectLoop();
});

async function disconnectAll() {
    try {
        if (serialReader) {
            await serialReader.cancel();
            serialReader = null;
        }
        if (serialPort) {
            await serialPort.close();
            serialPort = null;
        }
    } catch (e) {
        console.error(e);
    }
    // also disconnect BLE nodes
    try { await disconnectAllBle(); } catch (e) { console.warn('disconnectAllBle failed', e); }

    document.getElementById('connectionStatus').textContent = '未连接';
    document.getElementById('disconnectBtn').style.display = 'none';
    document.getElementById('serialBtn').disabled = false;
    document.getElementById('bleBtn').disabled = false;
    stopBleHeartbeatLoop();
    logDebug('Disconnected');
}

function processDataLine(line, sourceConnId = null) {
    if (!line) return;
    const parts = line.split('|');
    if (parts.length < 3) return;

    // Support both formats: nodeId|mac|rssi|type|... and mac|rssi|type|...
    let nodeId = parseInt(parts[0]);
    let mac, rssi, type, extra;
    if (isNaN(nodeId) && parts[0].includes(':') && parts.length >= 3) {
        nodeId = 0;
        mac = parts[0].trim().toUpperCase();
        rssi = parseInt(parts[1]);
        type = parts[2].trim().toUpperCase();
        extra = parts.slice(3).join('|').trim();
    } else {
        mac = parts[1].trim().toUpperCase();
        rssi = parseInt(parts[2]);
        type = parts[3].trim().toUpperCase();
        extra = parts.slice(4).join('|').trim();
    }
    let name = '';
    let advInfo = '';
    if (extra) {
        const uuidMatch = extra.match(/([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})/);
        if (uuidMatch) {
            advInfo = extra;
            name = extra.replace(uuidMatch[1], '').trim();
        } else {
            name = extra;
        }
    }
    
    if (isNaN(nodeId) || isNaN(rssi)) return;
    
    connectedNodes.add(nodeId);
    updateNodeCount();

    // 如果该行来自 BLE 连接（传入了 sourceConnId），更新该连接的 lastSeen
    if (sourceConnId) {
        const conn = bleConnections.get(sourceConnId);
        if (conn) conn.lastSeen = Date.now();
    }

    processDeviceData(nodeId, mac, rssi, type, name, advInfo);

    renderDeviceList();
}

function getDeviceKey(mac, type) {
    return `${type}:${mac}`;
}

function processDeviceData(nodeId, mac, rssi, type, name = '', advInfo = '') {
    const now = Date.now();
    const key = getDeviceKey(mac, type);
    let device = devices.get(key);
    
    if (!device) {
        device = {
            mac,
            brand: getBrandFromOUI(mac),
            name: name,
            type,
            nodes: new Map(),
            lastSeen: now,
            smoothedRssi: rssi,
            rssiHistory: [rssi],
            probeIntervals: [],
            avgProbeInterval: 0,
            rssiStdDev: 0,
            advInfo: advInfo,
            deviceClass: type === 'BLE' ? classifyBluetoothDevice(name, mac, advInfo) : 'WIFI',
            isPhoneOrTablet: type === 'BLE' ? isPhoneOrTablet(classifyBluetoothDevice(name, mac, advInfo)) : false
        };
    }
    
    if (name) {
        device.name = name;
    }
    if (advInfo) {
        device.advInfo = advInfo;
    }

    if (device.lastSeen) {
        const interval = now - device.lastSeen;
        device.probeIntervals.push(interval);
        if (device.probeIntervals.length > 5) {
            device.probeIntervals.shift();
        }
        const sumInterval = device.probeIntervals.reduce((acc, v) => acc + v, 0);
        device.avgProbeInterval = sumInterval / device.probeIntervals.length;
    }

    device.rssiHistory = device.rssiHistory || [];
    device.rssiHistory.push(rssi);
    if (device.rssiHistory.length > 5) {
        device.rssiHistory.shift();
    }
    const rssiAvg = device.rssiHistory.reduce((acc, v) => acc + v, 0) / device.rssiHistory.length;
    device.rssiStdDev = Math.sqrt(device.rssiHistory.reduce((acc, v) => acc + Math.pow(v - rssiAvg, 2), 0) / device.rssiHistory.length);

    device.nodes.set(nodeId, rssi);
    device.smoothedRssi = device.smoothedRssi * 0.7 + rssi * 0.3;
    device.lastSeen = now;
    device.type = type;
    if (type === 'BLE') {
        const classified = classifyBluetoothDevice(device.name, mac, device.advInfo);
        device.deviceClass = classified;
        device.isPhoneOrTablet = isPhoneOrTablet(classified);
        if (device.isPhoneOrTablet) {
            device.brand = getPhoneBrand(device.name, mac, device.advInfo);
        }
    }
    
    devices.set(key, device);
    updateDeviceCount();
    updateTypeCount();
}

function getBrandFromOUI(mac) {
    const oui = mac.substring(0, 8).toUpperCase();
    return OUI_DATABASE[oui] || '未知品牌';
}

function normalizeAdvText(text) {
    return text ? text.trim().replace(/\s+/g, ' ').toLowerCase() : '';
}

function normalizeHexText(text) {
    return text ? text.toLowerCase().replace(/[^0-9a-f]/g, '') : '';
}

function combineAdvText(name, advInfo) {
    return normalizeAdvText((name || '') + ' ' + (advInfo || ''));
}

function hasHexSequence(text, token) {
    return normalizeHexText(text).includes(token.toLowerCase());
}

function hasAllHexSequences(text, tokens) {
    return tokens.every(token => hasHexSequence(text, token));
}

function isAppleBroadcast(text, advInfo) {
    const raw = normalizeAdvText((text || '') + ' ' + (advInfo || ''));
    const hex = normalizeHexText(raw);
    const has180A = hex.includes('0000180a') || hex.includes('180a');
    const hasManufacturerCustom = hasWaveManufacturerData(raw);
    return has180A && !hasManufacturerCustom && raw.length < 80;
}

function hasWaveManufacturerData(text) {
    return /0xff|\bff[:\s-]?([0-9a-f]{2})/.test(text);
}

function classifyBluetoothDevice(name, mac, advInfo = '') {
    const text = combineAdvText(name, advInfo);
    if (!text) return 'BLE_OTHER';

    const appleKeywords = /\b(i(phone|pad|pod|watch)|airpods|apple)\b/;
    const tabletKeywords = /\b(tablet|ipad|galaxy tab|tab)\b/;
    const androidKeywords = /\b(pixel|sm-|galaxy|note|mi |redmi|huawei|honor|oppo|vivo|oneplus|realme|lenovo|moto|nokia|asus|sony|lg|zte|xiaomi|meizu|android)\b/;
    const genericPhone = /\b(phone|mobile|smartphone|p30|p40|mate|nova|a53|a73|s24|s23|pixel)\b/;
    const hex = normalizeHexText(text);

    const hasAppleUuid = hex.includes('0000180a') || hex.includes('180a');
    const hasHuaweiId = hasHexSequence(text, '9200') || hasHexSequence(text, '0092');
    const hasHuaweiUuid = hex.includes('00001999') || hex.includes('1999');
    const hasXiaomiId = hasHexSequence(text, '0097') || hasHexSequence(text, '4d49');
    const hasOppoId = hasAllHexSequences(text, ['0085', '0403']);
    const hasVivoId = hasAllHexSequences(text, ['0115', '0403']);
    const hasSamsungId = hasHexSequence(text, '0075');

    if (appleKeywords.test(text) || isAppleBroadcast(name, advInfo) || (hasAppleUuid && !hasHuaweiId && !hasXiaomiId && !hasOppoId && !hasVivoId && !hasSamsungId)) {
        return 'IOS_PHONE';
    }
    if (hasHuaweiId || hasHuaweiUuid) {
        return 'ANDROID_PHONE';
    }
    if (hasXiaomiId) {
        return 'ANDROID_PHONE';
    }
    if (hasOppoId) {
        return 'ANDROID_PHONE';
    }
    if (hasVivoId) {
        return 'ANDROID_PHONE';
    }
    if (hasSamsungId) {
        return 'ANDROID_PHONE';
    }
    if (tabletKeywords.test(text)) return 'TABLET';
    if (androidKeywords.test(text)) return 'ANDROID_PHONE';
    if (genericPhone.test(text)) return 'ANDROID_PHONE';

    const ouiBrand = getBrandFromOUI(mac);
    if (ouiBrand === 'Apple') return 'IOS_PHONE';
    if (['Samsung','Google','Xiaomi','Huawei','OPPO','Vivo','Realme','OnePlus','Sony','Nokia','LG','Motorola','Lenovo'].includes(ouiBrand)) return 'ANDROID_PHONE';

    return 'BLE_OTHER';
}

function isPhoneOrTablet(deviceClass) {
    return deviceClass === 'IOS_PHONE' || deviceClass === 'ANDROID_PHONE' || deviceClass === 'TABLET';
}

function getPhoneBrand(name, mac, advInfo = '') {
    const normalized = combineAdvText(name, advInfo);
    const hex = normalizeHexText(normalized);
    const appleKeywords = /\b(i(phone|pad|pod|watch)|airpods|apple)\b/;
    if (appleKeywords.test(normalized)) return 'Apple';
    if (isAppleBroadcast(name, advInfo) || hex.includes('0000180a') || hex.includes('180a')) return 'Apple';
    if (hasHexSequence(normalized, '9200') || hasHexSequence(normalized, '0092') || hex.includes('00001999') || hex.includes('1999')) return 'Huawei';
    if (hasHexSequence(normalized, '0097') || hasHexSequence(normalized, '4d49')) return 'Xiaomi';
    if (hasAllHexSequences(normalized, ['0085', '0403'])) return 'OPPO';
    if (hasAllHexSequences(normalized, ['0115', '0403'])) return 'Vivo';
    if (hasHexSequence(normalized, '0075')) return 'Samsung';
    const brandMap = {
        pixel: 'Google',
        samsung: 'Samsung',
        huawei: 'Huawei',
        honor: 'Honor',
        oppo: 'OPPO',
        vivo: 'Vivo',
        oneplus: 'OnePlus',
        realme: 'Realme',
        lenovo: 'Lenovo',
        moto: 'Moto',
        nokia: 'Nokia',
        asus: 'ASUS',
        sony: 'Sony',
        lg: 'LG',
        zte: 'ZTE',
        xiaomi: 'Xiaomi',
        meizu: 'Meizu',
        google: 'Google'
    };
    for (const key in brandMap) {
        if (normalized.includes(key)) return brandMap[key];
    }
    return getBrandFromOUI(mac);
}

function getDeviceClassLabel(device) {
    if (device.type === 'WIFI') return 'WiFi 探针';
    if (!device.deviceClass || device.deviceClass === 'BLE_OTHER') return '其他 BLE';
    if (device.deviceClass === 'IOS_PHONE') return 'iOS 手机';
    if (device.deviceClass === 'ANDROID_PHONE') return '安卓 手机';
    if (device.deviceClass === 'TABLET') return '平板';
    return 'BLE 设备';
}

function calculateDistance(rssi, rssiStdDev = 0) {
    const clippedRssi = Math.max(Math.min(rssi, -30), -100);
    const stability = Math.max(0, rssiStdDev);
    const confidence = Math.exp(-stability / 7);

    const correctedRssi = clippedRssi * confidence + settings.rssiAt1m * (1 - confidence);

    const weaknessFactor = Math.max(0, (-clippedRssi - 65) / 35);
    const dynamicExponent = settings.distanceParam + (1 - confidence) * 0.8 + weaknessFactor * 0.6;

    const ratio = (settings.rssiAt1m - correctedRssi) / (10 * dynamicExponent);
    let distance = Math.pow(10, ratio);

    const uncertaintyMultiplier = 1 + (1 - confidence) * 0.8;
    distance *= uncertaintyMultiplier;

    return Math.min(Math.max(distance, 0.1), 100);
}

function updateNodeCount() {
    document.getElementById('nodeCount').textContent = connectedNodes.size;
}

function updateDeviceCount() {
    document.getElementById('deviceCount').textContent = devices.size;
    document.getElementById('deviceTotal').textContent = `(${devices.size})`;
}

function updateTypeCount() {
    let wifiCount = 0, bleCount = 0;
    devices.forEach(dev => {
        if (dev.type === 'WIFI') wifiCount++;
        else if (dev.type === 'BLE' && (!settings.enableDeviceFilter || dev.isPhoneOrTablet)) bleCount++;
    });
    document.getElementById('wifiCount').textContent = wifiCount;
    document.getElementById('bleCount').textContent = bleCount;
}

function renderDeviceList() {
    const container = document.getElementById('deviceList');
    container.innerHTML = '';
    
    const now = Date.now();
    const timeoutMs = settings.timeoutSec * 1000;
    
    const filteredDevices = Array.from(devices.entries())
        .filter(([key, device]) => {
            if (now - device.lastSeen > timeoutMs) {
                devices.delete(key);
                return false;
            }
            if (currentFilter !== 'all' && device.type !== currentFilter) {
                return false;
            }
            if (device.type === 'BLE' && settings.enableDeviceFilter && !device.isPhoneOrTablet) {
                return false;
            }
            return true;
        });

    // Aggregate by MAC so desktop UI shows one entry per MAC (prefer WiFi)
    const macMap = new Map();
    filteredDevices.forEach(([key, device]) => {
        const mac = device.mac;
        const existing = macMap.get(mac);
        if (!existing) {
            macMap.set(mac, { ...device, types: new Set([device.type]) });
        } else {
            existing.types.add(device.type);
            if (device.type === 'WIFI' && existing.type !== 'WIFI') {
                macMap.set(mac, { ...device, types: existing.types });
            } else if (device.smoothedRssi > existing.smoothedRssi) {
                macMap.set(mac, { ...device, types: existing.types });
            }
        }
    });

    const aggregated = Array.from(macMap.values()).sort((a, b) => b.smoothedRssi - a.smoothedRssi);

    // Debug: detect duplicate MACs in original devices map (should be none after aggregation)
    const macCounts = {};
    filteredDevices.forEach(([k, d]) => { macCounts[d.mac] = (macCounts[d.mac] || 0) + 1; });
    const duplicates = Object.entries(macCounts).filter(([mac, c]) => c > 1);
    if (duplicates.length) {
        // throttle duplicate warnings to avoid spamming console
        if (settings.showDebug && (Date.now() - duplicateWarnTime > 5000)) {
            console.warn('Duplicate MACs detected before aggregation:', duplicates);
            duplicateWarnTime = Date.now();
        }
    }

    aggregated.forEach(device => {
        // compute per-node distances
        const nodeDistances = Array.from(device.nodes.entries()).map(([nid, nrssi]) => {
            return { nodeId: nid, rssi: nrssi, distance: parseFloat(calculateDistance(nrssi, device.rssiStdDev).toFixed(2)) };
        }).sort((a, b) => a.distance - b.distance);
        const distance = nodeDistances.length ? nodeDistances[0].distance.toFixed(2) : calculateDistance(device.smoothedRssi, device.rssiStdDev).toFixed(2);
        const label = device.name || device.brand;
        const subtitle = device.name ? device.brand : '';
        const classLabel = getDeviceClassLabel(device);
        const intervalLabel = device.avgProbeInterval ? `${Math.round(device.avgProbeInterval)}ms` : '--';
        const stabilityLabel = device.rssiStdDev ? device.rssiStdDev.toFixed(1) : '--';
        const item = document.createElement('div');
        item.className = 'device-item';

        let statsHtml = '';
        if (settings.showDebug) {
            statsHtml = `
                <div class="device-stats">
                    <span class="device-stat stat-${device.type.toLowerCase()}">${classLabel}</span>
                    <span class="device-stat">${device.smoothedRssi.toFixed(0)} dBm</span>
                    <span class="device-stat">${distance} m</span>
                    <span class="device-stat">${intervalLabel}</span>
                    <span class="device-stat">${stabilityLabel}</span>
                    <span class="device-stat">节点${Array.from(device.nodes.keys()).join(',')}</span>
                </div>
            `;
        } else {
            statsHtml = `
                <div class="device-stats">
                    <span class="device-stat stat-${device.type.toLowerCase()}">${device.type === 'WIFI' ? 'WiFi' : 'BLE'}</span>
                    <span class="device-stat">${device.smoothedRssi.toFixed(0)} dBm</span>
                    <span class="device-stat">${distance} m</span>
                    <span class="device-stat">节点${Array.from(device.nodes.keys()).join(',')}</span>
                </div>
            `;
        }

        // append per-node distance badges (compact)
        const nodeBadgesHtml = nodeDistances.map(nd => `<span class="node-badge">节点${nd.nodeId}:${nd.distance}m</span>`).join(' ');

        item.innerHTML = `
            <div class="device-info">
                <div class="device-mac">${device.mac}</div>
                ${settings.showDebug ? `<div class="device-brand">${label}</div>` : ''}
                ${settings.showDebug && subtitle ? `<div class="device-subbrand">${subtitle}</div>` : ''}
                ${statsHtml}
                <div class="device-node-badges">${nodeBadgesHtml}</div>
            </div>
        `;
        container.appendChild(item);
    });
    
    updateDeviceCount();
    updateTypeCount();
}

function updateDeviceList() {
    renderDeviceList();
    if (updateTimer) clearTimeout(updateTimer);
    updateTimer = setTimeout(updateDeviceList, settings.refreshRate);
}

function cleanup() {
    try {
        if (animationId) cancelAnimationFrame(animationId);
        if (updateTimer) clearTimeout(updateTimer);
    } catch (e) {
        console.error('Cleanup error', e);
    }
    // attempt to disconnect gracefully
    disconnectAll();
}

function toggleTheme() {
    isDarkMode = !isDarkMode;
    document.body.classList.toggle('dark-mode', isDarkMode);
}

function openSettings() {
    document.getElementById('settingsModal').style.display = 'block';
    document.getElementById('distanceParam').value = settings.distanceParam;
    document.getElementById('rssiAt1m').value = settings.rssiAt1m;
    document.getElementById('timeoutSec').value = settings.timeoutSec;
    document.getElementById('refreshRate').value = settings.refreshRate;
    document.getElementById('showDebug').checked = settings.showDebug;
    document.getElementById('enableDeviceFilter').checked = settings.enableDeviceFilter;
}

function closeSettings() {
    document.getElementById('settingsModal').style.display = 'none';
}

function saveSettings() {
    settings.distanceParam = parseFloat(document.getElementById('distanceParam').value);
    settings.rssiAt1m = parseInt(document.getElementById('rssiAt1m').value);
    settings.timeoutSec = parseInt(document.getElementById('timeoutSec').value);
    settings.refreshRate = parseInt(document.getElementById('refreshRate').value);
    settings.showDebug = document.getElementById('showDebug').checked;
    settings.enableDeviceFilter = document.getElementById('enableDeviceFilter').checked;
    
    localStorage.setItem('sightsentry_settings', JSON.stringify(settings));
    document.getElementById('debugPanel').style.display = settings.showDebug ? 'block' : 'none';
    closeSettings();
    renderDeviceList();
    logDebug('Settings saved');
}

function resetSettings() {
    settings = {
        distanceParam: 2.5,
        rssiAt1m: -59,
        timeoutSec: 30,
        refreshRate: 1000,
        showDebug: false,
        enableDeviceFilter: true
    };
    openSettings();
    renderDeviceList();
}

function loadSettings() {
    const saved = localStorage.getItem('sightsentry_settings');
    if (saved) {
        settings = { ...settings, ...JSON.parse(saved) };
    }
    document.getElementById('debugPanel').style.display = settings.showDebug ? 'block' : 'none';
}

function clearDebugLog() {
    document.getElementById('debugLog').innerHTML = '';
}

function logDebug(message) {
    if (!settings.showDebug) return;
    const log = document.getElementById('debugLog');
    const time = new Date().toLocaleTimeString();
    log.innerHTML = `[${time}] ${message}\n` + log.innerHTML;
    if (log.innerHTML.length > 5000) {
        log.innerHTML = log.innerHTML.substring(0, 5000);
    }
}

function detectPlatform() {
    if (window.__TAURI__) {
        return 'tauri';
    } else if (navigator.userAgent.includes('Android')) {
        return 'android';
    } else {
        return 'web';
    }
}

const platform = detectPlatform();

if (platform === 'tauri') {
    setupTauriWindowControls();
} else if (platform === 'android') {
    setupAndroidBridge();
} else {
    // Web-specific initialization
}

function setupAndroidBridge() {
    document.querySelectorAll('#minimizeBtn, #maximizeBtn, #closeBtn').forEach(btn => {
        btn.style.display = 'none';
    });

    if (window.__nativeBridge) {
        const info = JSON.parse(window.__nativeBridge.getNativeInfo());
        console.log('Android native bridge ready:', info);
        logDebug('Android native bridge initialized');
    } else {
        console.warn('Native bridge not available - running in limited mode');
        logDebug('Native bridge unavailable');
    }
}

function callNative(action, params = {}) {
    if (!window.__nativeBridge) {
        return Promise.reject(new Error('Native bridge not available'));
    }

    const message = JSON.stringify({ action, ...params });
    try {
        const responseStr = window.__nativeBridge.callNative(message);
        const response = JSON.parse(responseStr);
        if (response.error) {
            return Promise.reject(new Error(response.error));
        }
        return Promise.resolve(response.result || response);
    } catch (e) {
        return Promise.reject(e);
    }
}
