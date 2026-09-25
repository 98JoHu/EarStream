package edu.kit.teco.openWearable

import android.content.Context
import android.content.res.AssetManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Copies the bundled Kokoro-82M voice model out of the APK so ONNX Runtime can
 * open it by path.
 *
 * The model is shipped under `src/main/assets/` rather than as a Flutter asset
 * for two reasons: it is a tree of several hundred files (espeak-ng's phoneme
 * data), which Flutter's `assets:` declarations do not recurse into, and its
 * ONNX graph is about 330 MB, which `rootBundle.load` would have to hold in
 * memory in one piece. `AssetManager` can walk the tree and stream each file,
 * so this copy runs in constant memory.
 *
 * The copy happens once, and a completion marker lets later launches skip even
 * the directory walk. Everything runs off the main thread; a build without the
 * asset directory simply reports that nothing is bundled.
 */
class KokoroModelInstaller(
  private val context: Context,
  messenger: BinaryMessenger,
) {
  companion object {
    const val CHANNEL = "edu.kit.teco.open_wearable/kokoro_model"

    /**
     * The directory name inside src/main/assets, and the name it keeps in
     * app storage. Dart never needs it: [install] hands back the resolved
     * absolute path, and the file names within it live in
     * OverallMeditationConfig.
     */
    private const val MODEL_DIRECTORY = "kokoro-multi-lang-v1_0"

    private const val COPY_BUFFER_BYTES = 256 * 1024

    /**
     * Written once the whole tree is in place. Bump the contents to force a
     * reinstall after the bundled model is replaced with a different one.
     */
    private const val COMPLETION_MARKER = ".installed"
    private const val MARKER_CONTENTS = "kokoro-multi-lang-v1_0/1"
  }

  private val worker = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())

  init {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "status" -> runOnWorker(result) { mapOf("bundled" to isBundled()) }
        "install" -> runOnWorker(result) { install() }
        else -> result.notImplemented()
      }
    }
  }

  private fun runOnWorker(
    result: MethodChannel.Result,
    work: () -> Map<String, Any?>,
  ) {
    worker.execute {
      val reply = try {
        Result.success(work())
      } catch (error: Exception) {
        Result.failure(error)
      }
      mainHandler.post {
        reply.fold(
          onSuccess = { result.success(it) },
          onFailure = { result.error("kokoro_model", it.message, null) },
        )
      }
    }
  }

  /** Whether the model directory was packaged into this build at all. */
  private fun isBundled(): Boolean = assetChildren(MODEL_DIRECTORY).isNotEmpty()

  private fun install(): Map<String, Any?> {
    if (!isBundled()) return mapOf("directory" to null)

    val target = File(context.filesDir, MODEL_DIRECTORY)
    val marker = File(target, COMPLETION_MARKER)
    if (marker.isFile && marker.readText() == MARKER_CONTENTS) {
      return mapOf("directory" to target.absolutePath, "filesCopied" to 0)
    }

    val copied = copyAssetTree(MODEL_DIRECTORY, target)
    // Only now is the tree known to be complete. Until this exists, a later
    // launch re-walks the assets rather than trusting a partial copy.
    marker.writeText(MARKER_CONTENTS)
    return mapOf(
      "directory" to target.absolutePath,
      "filesCopied" to copied,
    )
  }

  /**
   * Lists an asset directory's children, treating "not a directory" and "does
   * not exist" alike: AssetManager reports both as an empty list or throws.
   */
  private fun assetChildren(path: String): Array<String> = try {
    context.assets.list(path) ?: emptyArray()
  } catch (_: IOException) {
    emptyArray()
  }

  /** Recursively copies [assetPath] into [target]; returns files written. */
  private fun copyAssetTree(assetPath: String, target: File): Int {
    val children = assetChildren(assetPath)
    if (children.isEmpty()) {
      return if (copyAssetFile(assetPath, target)) 1 else 0
    }

    if (!target.isDirectory && !target.mkdirs()) {
      throw IOException("Could not create ${target.absolutePath}")
    }
    var copied = 0
    for (child in children) {
      copied += copyAssetTree("$assetPath/$child", File(target, child))
    }
    return copied
  }

  /**
   * Copies one asset, skipping it when it is already there.
   *
   * The write goes to a temporary name and is then renamed, so a file that
   * exists is by construction a complete one: an interrupted copy leaves a
   * `.partial` behind rather than a truncated model. That is what makes the
   * plain existence check safe, and it avoids having to decompress a 330 MB
   * asset just to compare its length.
   */
  private fun copyAssetFile(assetPath: String, target: File): Boolean {
    if (target.isFile) return false

    target.parentFile?.mkdirs()
    val temporary = File(target.parentFile, "${target.name}.partial")
    context.assets.open(assetPath, AssetManager.ACCESS_STREAMING).use { input ->
      temporary.outputStream().use { output ->
        val buffer = ByteArray(COPY_BUFFER_BYTES)
        while (true) {
          val read = input.read(buffer)
          if (read < 0) break
          output.write(buffer, 0, read)
        }
        output.flush()
      }
    }
    if (!temporary.renameTo(target)) {
      temporary.delete()
      throw IOException("Could not move ${temporary.name} into place")
    }
    return true
  }
}
