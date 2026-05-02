android {
    compileSdkVersion 34
    targetSdkVersion 34
    minSdkVersion 28
    
    ndkVersion = "25.2.9519663"
    
    buildToolsVersion = "34.0.0"
    
    defaultConfig {
        applicationId = "com.sightsentry.pro"
        manifestPlaceholders += [
            bluetoothScanPermission: "android.permission.BLUETOOTH_SCAN",
            bluetoothConnectPermission: "android.permission.BLUETOOTH_CONNECT",
            bluetoothPermission: "android.permission.BLUETOOTH",
            accessFineLocationPermission: "android.permission.ACCESS_FINE_LOCATION",
            accessCoarseLocationPermission: "android.permission.ACCESS_COARSE_LOCATION",
            nearbyWifiDevicesPermission: "android.permission.NEARBY_WIFI_DEVICES"
        ]
    }
    
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    
    kotlinOptions {
        jvmTarget = "17"
    }
    
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

if (project.hasProperty("ANDROID_HOME")) {
    Properties properties = new Properties()
    properties.load(file("local.properties").newDataInputStream())
    android.sdkDirectory = properties.getProperty("sdk.dir")
}
