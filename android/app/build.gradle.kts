import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: upload key settings live in android/key.properties, which is
// git-ignored. Template: android/key.properties.example.
// Guide: docs/release/android-release-signing.md
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        // UTF-8 so a Korean folder name in storeFile is read correctly.
        keystorePropertiesFile.reader(Charsets.UTF_8).use { load(it) }
    }
}
val missingReleaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
val releaseStoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { rootProject.file(it) }
val hasReleaseSigning = keystorePropertiesFile.exists() &&
    missingReleaseSigningKeys.isEmpty() &&
    releaseStoreFile?.exists() == true

android {
    namespace = "com.jesuslab.neorangnarang"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jesuslab.neorangnarang"
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

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Upload key only. Without android/key.properties the release
            // build stops (see the task graph check below) instead of using
            // the debug key.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
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

// Release builds must never fall back to the debug key. Stop before building
// a release APK/AAB when android/key.properties is missing or incomplete.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.project == project &&
            task.name.endsWith("Release") &&
            (task.name.startsWith("assemble") || task.name.startsWith("bundle") || task.name.startsWith("package"))
    }
    if (buildsRelease && !hasReleaseSigning) {
        val reason = when {
            !keystorePropertiesFile.exists() -> "android/key.properties 파일이 없습니다"
            missingReleaseSigningKeys.isNotEmpty() -> "android/key.properties에 빈 항목이 있습니다: ${missingReleaseSigningKeys.joinToString()}"
            else -> "storeFile 경로에 키 파일이 없습니다: ${keystoreProperties.getProperty("storeFile")}"
        }
        throw GradleException("release 서명 설정이 필요합니다. $reason. docs/release/android-release-signing.md를 참고하세요.")
    }
}
