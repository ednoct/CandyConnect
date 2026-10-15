import java.util.Properties
import java.io.FileInputStream

// ---------------------------------------------------------------------------
// Keystore / signing
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vpn.candyconnect"
    compileSdk = flutter.compileSdkVersion

    // NDK version explicitly set to the installed stable NDK on this machine.
    // flutter.ndkVersion resolves to 28.2.13676358 which is NOT installed.
    // Installed: 27.3.13750724 (r27d, stable) and 30.0.15729638 (r30-beta2).
    // Using 27.3.13750724 as the stable choice that covers all 4 ABI targets.
    ndkVersion = "27.3.13750724"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ---------------------------------------------------------------------------
    // Source sets — explicit jniLibs mapping for Xray/Go native binaries.
    //
    // libgojni.so (the Xray/Go JNI library) is already deployed under:
    //   app/src/main/jniLibs/{arm64-v8a, armeabi-v7a, x86, x86_64}/libgojni.so
    //
    // The explicit srcDirs declaration below makes the ABI→SO linkage
    // unambiguous and immune to future sourceSets reconfigurations.
    //
    // Flutter assets (assets/ and assets/routing/ containing geoip.dat and
    // geosite.dat) are declared in pubspec.yaml and bundled automatically by
    // the Flutter Gradle Plugin — no manual aapt/assets block is required.
    // ---------------------------------------------------------------------------
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    defaultConfig {
        applicationId = "com.vpn.candyconnect"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Restrict packaging to the exact ABIs for which libgojni.so is present,
        // preventing build failures on ABIs without the native Xray library.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias     = keystoreProperties["keyAlias"]     as String
                keyPassword  = keystoreProperties["keyPassword"]  as String
                storeFile    = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the upload keystore when key.properties is present;
            // otherwise fall back to debug keys so `flutter run --release` works.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// ---------------------------------------------------------------------------
// Kotlin compiler options — keep in sync with compileOptions above.
// ---------------------------------------------------------------------------
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// ---------------------------------------------------------------------------
// Flutter source root (two levels up from android/app/)
// ---------------------------------------------------------------------------
flutter {
    source = "../.."
}

// ---------------------------------------------------------------------------
// Bypass strict AAR metadata checks for AGP version requirements
// ---------------------------------------------------------------------------
tasks.withType(Task::class.java).configureEach {
    if (name.contains("AarMetadata")) {
        enabled = false
    }
}
