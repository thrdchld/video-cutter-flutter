plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.video_cutter_flutter"

    // compileSdk must be 36+ for plugin compatibility
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.video_cutter_flutter"
        // Ensure minSdk meets FFmpegKit requirement (>=24)
        minSdk = 24
        // targetSdk must be 36+ for plugin compatibility
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
        // Disable resource shrinking unless code shrinking (minify) is enabled
        isMinifyEnabled = false
        isShrinkResources = false
            // Use debug signing for local testing; replace with release keystore for Play Store
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
        }
    }

    // Optional: enable packagingOptions if necessary for native libs
    packagingOptions {
        resources {
            excludes += setOf("META-INF/*.kotlin_module")
        }
    }
}

flutter {
    source = "../.."
}
