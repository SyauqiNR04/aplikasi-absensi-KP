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

// Beberapa plugin (mis. tflite_flutter) masih mendeklarasikan Java 1.8 secara
// eksplisit sementara Kotlin Gradle plugin memakai default JVM target dari JDK
// yang menjalankan Gradle (mis. 21), menyebabkan
// "Inconsistent JVM Target Compatibility Between Java and Kotlin Tasks".
// Paksa semua subproject (termasuk plugin pihak ketiga) konsisten ke 17.
// Harus didaftarkan SEBELUM evaluationDependsOn(":app") di bawah, karena itu
// mengevaluasi ":app" segera dan afterEvaluate tak bisa dipasang lagi setelahnya.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
