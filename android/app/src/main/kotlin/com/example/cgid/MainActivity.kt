package com.example.cgid

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.pm.PackageManager
import java.util.Calendar

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "org.cgid.cgid/branding")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSabbathIcon") {
                    updateIcon()
                    result.success(null)
                } else result.notImplemented()
            }
    }
    override fun onResume() { super.onResume(); updateIcon() }
    private fun updateIcon() {
        val gold = Calendar.getInstance().get(Calendar.DAY_OF_WEEK) == Calendar.SATURDAY
        val active = if (gold) "GoldLauncher" else "BlueLauncher"
        val inactive = if (gold) "BlueLauncher" else "GoldLauncher"
        packageManager.setComponentEnabledSetting(ComponentName(this, "$packageName.$active"),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        packageManager.setComponentEnabledSetting(ComponentName(this, "$packageName.$inactive"),
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
    }
}
