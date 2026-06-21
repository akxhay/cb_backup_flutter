allprojects {
    repositories {
        google()
        mavenCentral()
        // Extra repositories for old/unmaintained plugins (video_thumbnail etc.)
        maven { url = uri("https://maven.aliyun.com/repository/public") }
    }
}

// Workaround for very old plugins (like video_thumbnail) that still reference jcenter in their build files
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library") || project.plugins.hasPlugin("com.android.application")) {
            // nothing needed
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
