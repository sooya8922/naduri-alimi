plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sooya8922.naduri"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications가 java.time 등 최신 API 사용 → 데스가링 필수 (chwiso 실측)
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.sooya8922.naduri"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 고정 업로드 키 (CI가 KEYSTORE_PATH/KEYSTORE_PASSWORD env로 주입).
    // 러너마다 임시 debug키가 새로 생겨 업데이트 설치가 거부되던 문제(chwiso M4 실측)의 근본 해결.
    val ciKeystorePath: String? = System.getenv("KEYSTORE_PATH")
    signingConfigs {
        if (ciKeystorePath != null) {
            create("upload") {
                storeFile = file(ciKeystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = "upload"
                keyPassword = System.getenv("KEYSTORE_PASSWORD")
                storeType = "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            // CI: 고정 upload 키 / 로컬(키 없음): debug 키 폴백
            signingConfig = if (ciKeystorePath != null) signingConfigs.getByName("upload")
                            else signingConfigs.getByName("debug")
            // chwiso M4 실기기 크래시 대응: R8 축소가 flutter_local_notifications 내부(GSON TypeToken)를
            // 제거해 시작 크래시를 유발하는 알려진 문제 → MVP는 축소 비활성(+proguard 규칙도 동봉).
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
