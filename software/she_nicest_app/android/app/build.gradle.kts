plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.shenicest.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.shenicest.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStoreFile = System.getenv("WANYU_RELEASE_STORE_FILE")
    val releaseStorePassword = System.getenv("WANYU_RELEASE_STORE_PASSWORD")
    val releaseKeyAlias = System.getenv("WANYU_RELEASE_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("WANYU_RELEASE_KEY_PASSWORD")
    val releaseSigningConfigured = listOf(
        releaseStoreFile,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { !it.isNullOrBlank() }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    tasks.register("assertReleaseSigningConfigured") {
        doLast {
            if (!releaseSigningConfigured) {
                throw GradleException(
                    "Release signing is not configured. Set WANYU_RELEASE_STORE_FILE, " +
                        "WANYU_RELEASE_STORE_PASSWORD, WANYU_RELEASE_KEY_ALIAS, and " +
                        "WANYU_RELEASE_KEY_PASSWORD before building a release artifact.",
                )
            }
        }
    }

    tasks.configureEach {
        if (name == "assembleRelease" || name == "bundleRelease") {
            dependsOn("assertReleaseSigningConfigured")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
