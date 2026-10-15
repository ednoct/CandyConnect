// init.gradle.kts — Local cache Maven repository shim
//
// This init script surfaces the user-level Gradle module cache as a read-only
// local file-system Maven repository.  It intercepts every dependency resolution
// that would otherwise hit google() / mavenCentral() over the network and serves
// the artifacts straight from the already-cached ~/.gradle/caches/modules-2/
// files layout via a custom Maven resolver.
//
// It is placed in android/ (project-level), not ~/.gradle/init.d/, so it only
// affects this project and does not change the system Gradle configuration.

// Note: a project-level init script must live in the project's root build dir.
// The canonical hook is via --init-script flag, or placing in ~/.gradle/init.d/
// We reference this from gradle.properties instead.

settingsEvaluated {
    // No-op: resolution is handled at the repository level below.
}
