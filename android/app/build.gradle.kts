import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// ─────────────────────────────────────────────────────────────────────────────
// FIRMA DE RELEASE
// Antes el build de release se firmaba con la clave de DEBUG: cualquiera con
// el keystore de debug estándar podría firmar una versión modificada y Google
// Play la rechaza. Ahora se lee android/key.properties (NO subir a git):
//
//   storePassword=...
//   keyPassword=...
//   keyAlias=upload
//   storeFile=/ruta/absoluta/upload-keystore.jks
//
// Crear la clave:
//   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
//           -keysize 2048 -validity 10000 -alias upload
// Si no existe key.properties (p. ej. en local), se sigue usando debug para
// poder compilar, pero NO publiques ese binario.
// ─────────────────────────────────────────────────────────────────────────────
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hayClaveRelease = keystorePropertiesFile.exists()
if (hayClaveRelease) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // AVISO: "com.example" lo rechaza Google Play. Cambiarlo exige registrar
    // una app Android nueva en Firebase y sustituir google-services.json.
    namespace = "com.example.warzero"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        // flutter_local_notifications (v17+) usa APIs de Java 8+ que en Android
        // requieren "desugaring" de la librería base.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
    defaultConfig {
        applicationId = "com.example.warzero"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        create("release") {
            if (hayClaveRelease) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (hayClaveRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Necesaria para el core library desugaring que exige flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}