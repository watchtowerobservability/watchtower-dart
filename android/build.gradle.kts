// Flutter plugin layer over the native Android SDK (sdks/android, mirrored as watchtower-android):
// native crashes and ANRs, and the crash-loop guard the Dart client reads.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.watchtower.flutter"
    compileSdk = 34
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("dev.watchtower:watchtower-android:0.1.0")
}
