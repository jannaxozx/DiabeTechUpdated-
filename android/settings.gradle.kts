// settings.gradle

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal() // Needed for non-Android plugins
    }
    plugins {
        id 'com.android.application' version '8.2.0'
        id 'org.jetbrains.kotlin.android' version '1.9.10'
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = 'diabetechapp'
include ':app'
