plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ar_synth"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ar_synth"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // hand_landmarker (MediaPipe) requires a modern minSdk.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // A fixed, intentionally-shared key committed to the repo so that every
        // CI build carries the SAME signature — Android only allows an update to
        // install over an existing app when the signatures match.
        //
        // This is NOT a production key: the password is public. Never publish
        // this app to the Play Store with it; generate a private keystore and
        // load it from CI secrets instead.
        create("shared") {
            storeFile = file("arsynth-shared.jks")
            storePassword = "arsynth"
            keyAlias = "arsynth"
            keyPassword = "arsynth"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("shared")
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
