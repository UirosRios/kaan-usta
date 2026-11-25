plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "tr.edu.yildiz.kaan_usta"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "tr.edu.yildiz.kaan_usta"
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

    // Sabit imza anahtarı (kaan_usta.jks): her derleme aynı anahtarla imzalanır, yeni APK eskisinin üstüne kurulur ve
    // telefondaki kayıtlar silinmez. Anahtar ve parolası BİLEREK depoda ve herkese açık (kullanıcı kararı, 25 Kasım 2026):
    // uygulama Play Store'da değil, tez için elden dağıtılıyor. Anahtar değiştirilirse telefondaki uygulama kaldırılmadan
    // yeni APK kurulamaz (kaldırmak uygulama klasörünü siler).
    signingConfigs {
        create("release") {
            storeFile = file("kaan_usta.jks")
            storePassword = "kaanusta-acik"
            keyAlias = "kaan_usta"
            keyPassword = "kaanusta-acik"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
