package edu.kit.teco.openWearable

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Reports where audio is actually being routed, for the meditation app's
 * opt-in biosignal trace.
 *
 * This exists because PPG delivery collapses from 200 Hz to ~67 Hz in some
 * sessions a few seconds after audio starts, and never in others, with the
 * same app build and the same earbud. Nothing in the Dart layer can observe
 * which output device Android actually chose, so the cause could not be
 * separated from the trace alone.
 *
 * Strictly observational: it reads state and never changes routing, volume,
 * focus, or any Bluetooth profile.
 */
class AudioRouteDiagnostics(
  private val context: Context,
  messenger: BinaryMessenger,
) {
  companion object {
    const val CHANNEL = "edu.kit.teco.open_wearable/audio_route"

    private fun deviceTypeName(type: Int): String = when (type) {
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "builtin_speaker"
      AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "builtin_earpiece"
      AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired_headset"
      AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired_headphones"
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth_sco"
      AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth_a2dp"
      AudioDeviceInfo.TYPE_USB_DEVICE -> "usb_device"
      AudioDeviceInfo.TYPE_USB_HEADSET -> "usb_headset"
      AudioDeviceInfo.TYPE_HEARING_AID -> "hearing_aid"
      26 -> "ble_headset" // TYPE_BLE_HEADSET, API 31
      27 -> "ble_speaker" // TYPE_BLE_SPEAKER, API 31
      30 -> "ble_broadcast" // TYPE_BLE_BROADCAST, API 33
      else -> "type_$type"
    }

    private fun profileStateName(state: Int): String = when (state) {
      BluetoothProfile.STATE_CONNECTED -> "connected"
      BluetoothProfile.STATE_CONNECTING -> "connecting"
      BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
      BluetoothProfile.STATE_DISCONNECTED -> "disconnected"
      else -> "unknown_$state"
    }
  }

  init {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      if (call.method == "describe") {
        result.success(
          try {
            describe()
          } catch (error: Throwable) {
            // A diagnostic must never take the app down with it.
            mapOf("error" to (error.message ?: error.javaClass.simpleName))
          },
        )
      } else {
        result.notImplemented()
      }
    }
  }

  private fun describe(): Map<String, Any?> {
    val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val outputs = audio
      .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
      .map { deviceTypeName(it.type) }

    val result = mutableMapOf<String, Any?>(
      "output_devices" to outputs.distinct(),
      "music_active" to audio.isMusicActive,
      "audio_mode" to audio.mode,
      // Deprecated but still the clearest single signal on older releases.
      @Suppress("DEPRECATION")
      "bluetooth_a2dp_on" to audio.isBluetoothA2dpOn,
      "bluetooth_audio_connected" to outputs.any {
        it == "bluetooth_a2dp" || it.startsWith("ble_")
      },
    )

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      result["communication_device"] =
        audio.communicationDevice?.let { deviceTypeName(it.type) }
    }

    // Profile states say whether a Bluetooth audio link is established at all,
    // which distinguishes "routed to the earbud" from "earbud merely paired".
    try {
      val adapter = BluetoothAdapter.getDefaultAdapter()
      if (adapter != null) {
        result["a2dp_profile"] =
          profileStateName(adapter.getProfileConnectionState(BluetoothProfile.A2DP))
        if (Build.VERSION.SDK_INT >= 33) {
          // BluetoothProfile.LE_AUDIO, API 33.
          result["le_audio_profile"] =
            profileStateName(adapter.getProfileConnectionState(22))
        }
      }
    } catch (error: SecurityException) {
      result["bluetooth_profile_error"] = "permission_denied"
    }

    return result
  }
}
