// android/build.gradle.kts  (RAÍZ del módulo Android, NO el de app/)
//
// Ojo: aquí NO va ningún bloque `plugins { }`. Los plugins (com.android.application,
// kotlin-android, dev.flutter.flutter-gradle-plugin, google-services) se declaran en
// android/settings.gradle.kts (con `apply false`) y se APLICAN en android/app/build.gradle.kts.
// Si se aplican también aquí, el plugin de Flutter registra la tarea `generateLockfiles`
// dos veces y el build falla con "Cannot add task 'generateLockfiles'…".

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}