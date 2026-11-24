package __PACKAGE__

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity: la lettura continua a schermo spento.
// Il canale "dvoce/edge" apre i libri in Microsoft Edge e riceve il link
// "Torna a D. Voce" con la posizione raggiunta.
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var initialLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialLink = intent?.data?.takeIf { it.scheme == "dvoce" }?.toString()
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dvoce/edge")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "openInEdge" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.success(false)
                    } else {
                        try {
                            val i = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            i.setPackage("com.microsoft.emmx")
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.success(false)
                        }
                    }
                }
                "openEdgeStore" -> {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.microsoft.emmx")))
                    } catch (e: ActivityNotFoundException) {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=com.microsoft.emmx")))
                    }
                    result.success(true)
                }
                "initialLink" -> {
                    result.success(initialLink)
                    initialLink = null
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = intent.data
        if (data != null && data.scheme == "dvoce") {
            channel?.invokeMethod("link", data.toString())
        }
    }
}
