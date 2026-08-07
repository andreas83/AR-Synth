allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins still compile against an older compileSdk (e.g. flutter_soloud
// 2.x targets android-33), but newer transitive androidx libraries require
// compileSdk >= 34. Force every plugin subproject to compile against API 35 so
// the build succeeds. The app module is left alone (it uses
// flutter.compileSdkVersion). withGroovyBuilder avoids needing the Android
// Gradle Plugin types on the root build script's classpath.
subprojects {
    if (name != "app") {
        afterEvaluate {
            val androidExtension = extensions.findByName("android")
            if (androidExtension != null) {
                androidExtension.withGroovyBuilder {
                    "compileSdkVersion"(35)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
