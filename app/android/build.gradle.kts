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
    
    project.plugins.withId("com.android.library") {
        if (project.name == "background_sms") {
            try {
                val android = project.extensions.getByName("android")
                val setNamespaceMethod = android.javaClass.getMethod("setNamespace", String::class.java)
                setNamespaceMethod.invoke(android, "com.background_sms")
            } catch (e: Exception) {
                println("Failed to set namespace for background_sms: ${e.message}")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
