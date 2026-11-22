import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val releaseKey = Properties().apply {
    if (keyPropertiesFile.isFile) keyPropertiesFile.reader(Charsets.UTF_8).use { load(it) }
}

android {
    namespace = "com.localpharmacy.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.localpharmacy.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyPropertiesFile.isFile) {
            create("production") {
                storeType = "PKCS12"
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = rootProject.file(releaseKey.getProperty("passwordFile")).readText().trim()
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = storePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("production")
        }
    }
}

gradle.taskGraph.whenReady {
    if (!keyPropertiesFile.isFile && allTasks.any {
        it.project == project && it.name in setOf("assembleRelease", "bundleRelease", "packageRelease")
    }) {
        throw GradleException("Release signing requires android/key.properties. See android/key.properties.example.")
    }
}

flutter {
    source = "../.."
}
