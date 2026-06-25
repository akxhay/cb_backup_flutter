allprojects {
    repositories {
        google()
        mavenCentral()
        // Extra repositories for old/unmaintained plugins
        maven { url = uri("https://maven.aliyun.com/repository/public") }
    }

    // Force consistent JVM 17 for Java and Kotlin across all modules/plugins
    // This fixes "Inconsistent JVM-target compatibility" errors (e.g. with receive_sharing_intent)
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }

    // Modern compilerOptions DSL (required with Kotlin 2.x+)
    // See: https://kotl.in/u1r8ln
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

// Workaround for old plugins that may reference deprecated repositories
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
