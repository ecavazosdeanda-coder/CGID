{{flutter_js}}
{{flutter_build_config}}

// Offline caching is owned by sw.js. Do not register a competing Flutter worker.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += '?release=2.0.0-rc.3';
}
_flutter.loader.load();
