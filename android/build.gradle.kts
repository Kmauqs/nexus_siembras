allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Fuerza compileSdk = 36 en TODOS los subproyectos (plugins Flutter).
// Necesario porque file_picker 8.x depende de flutter_plugin_android_lifecycle
// que exige compileSdk >= 36. Sin esto, cada plugin se compila con su propio
// default (34) y falla el checkDebugAarMetadata.
subprojects {
    afterEvaluate {
        if (extensions.findByName("android") != null) {
            @Suppress("UNCHECKED_CAST")
            val androidExt = extensions.getByName("android") as com.android.build.gradle.BaseExtension
            androidExt.compileSdkVersion(36)
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
