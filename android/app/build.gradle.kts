import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    println("key.properties not found. Please create it in the android directory.")
}

fun signingConfigValue(envName: String, propertyName: String): String? {
    val envValue = System.getenv(envName)?.takeIf { it.isNotBlank() }
    if (envValue != null) return envValue
    return (keystoreProperties[propertyName] as? String)?.takeIf { it.isNotBlank() }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

android {
    namespace = "com.anerycoft.coursehelper"
    // 插件子项目被根 build.gradle.kts 强制 compileSdk 37，保持一致
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.anerycoft.coursehelper"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val releaseStorePassword = requireNotNull(
                signingConfigValue("STORE_PASSWORD", "storePassword")
            ) { "Missing signing value: STORE_PASSWORD/storePassword" }
            val releaseKeyAlias = requireNotNull(
                signingConfigValue("KEY_ALIAS", "keyAlias")
            ) { "Missing signing value: KEY_ALIAS/keyAlias" }
            val releaseKeyPassword = signingConfigValue("KEY_PASSWORD", "keyPassword")
                ?.ifBlank { null } ?: releaseStorePassword
            val releaseStoreFile = requireNotNull(
                signingConfigValue("KEYSTORE_PATH", "storeFile")
            ) { "Missing signing value: KEYSTORE_PATH/storeFile" }

            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
            storeFile = file(releaseStoreFile)
            storePassword = releaseStorePassword
        }
    }


    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // signingConfig = signingConfigs.getByName("debug")
            
            // 启用代码混淆
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            
            // 禁用 lint 检查以加快构建速度并避免文件锁定问题
            lint {
                checkDependencies = false
                abortOnError = false
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.baidu.lbsyun:BaiduMapSDK_Map:8.2.0")
    // flutter_bmflocation 插件已包含 BaiduMapSDK_Location_All
    implementation("com.baidu.lbsyun:BaiduMapSDK_Util:7.6.7")
}
