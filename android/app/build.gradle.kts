plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

fun readDotenvValue(dotenvFile: File, key: String): String? {
    if (!dotenvFile.exists()) return null

    // NOTE: Kotlin does not allow non-local returns from forEachLine lambdas in this context.
    // Use a plain loop so we can return from the function.
    for (line in dotenvFile.readLines()) {
        val trimmed = line.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#")) continue

        val idx = trimmed.indexOf('=')
        if (idx <= 0) continue

        val k = trimmed.substring(0, idx).trim()
        if (k != key) continue

        var v = trimmed.substring(idx + 1).trim()
        // Strip optional surrounding quotes
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith('\'') && v.endsWith('\''))) {
            v = v.substring(1, v.length - 1)
        }
        return v
    }

    return null
}

android {
    namespace = "com.example.transport_daily_report"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.transport_daily_report"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // OnBackInvokedCallbackの有効化
        manifestPlaceholders["enableOnBackInvokedCallback"] = true

        // Google Maps API Key (Android)
        // Source of truth: project root .env (loaded by flutter_dotenv at runtime)
        // This ensures we can put the key in .env and still inject it into AndroidManifest.
        val dotenv = rootProject.file("../.env")
        val mapsKey = readDotenvValue(dotenv, "GOOGLE_MAPS_API_KEY_ANDROID")

        if (mapsKey.isNullOrBlank()) {
            logger.warn("[maps] GOOGLE_MAPS_API_KEY_ANDROID is not set in .env. Google Maps may fail to load.")
            manifestPlaceholders["MAPS_API_KEY"] = ""
        } else {
            // Do not print the key.
            manifestPlaceholders["MAPS_API_KEY"] = mapsKey
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}
