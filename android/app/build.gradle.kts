import java.util.Properties
import java.io.FileInputStream

// ---------------------------------------------------------------------------
// Keystore / signing (ایمن‌سازی شده برای ویندوز محلی و لینوکس GitHub Actions)
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val configuredStorePath = keystoreProperties.getProperty("storeFile")
val resolvedStoreFile = if (!configuredStorePath.isNullOrBlank()) {
    file(configuredStorePath)
} else {
    null
}
val hasValidReleaseKeystore =
    keystorePropertiesFile.exists() && resolvedStoreFile != null && resolvedStoreFile.exists()

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vpn.candyconnect"
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = "27.3.13750724"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    // تضمین استخراج مستقیم و فشرده‌نشده libXray.so در تمامی معماری‌ها برای کارکرد بی‌نقص Dart FFI
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    defaultConfig {
        applicationId = "com.vpn.candyconnect"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = maxOf(flutter.targetSdkVersion, 35)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasValidReleaseKeystore && resolvedStoreFile != null) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = resolvedStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasValidReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

tasks.withType(Task::class.java).configureEach {
    if (name.contains("AarMetadata")) {
        enabled = false
    }
}