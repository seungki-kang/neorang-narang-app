package com.jesuslab.neorangnarang

import android.content.Context
import android.content.pm.ApplicationInfo
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Debug gated, app-private, no logs and no exported IPC. */
object CommonSessionVault {
    fun install(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "jesuslife/session_vault")
            .setMethodCallHandler { call, result ->
                if ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
                    result.error("disabled", "Session storage unavailable", null)
                    return@setMethodCallHandler
                }
                try {
                    val binding = requireNotNull(call.argument<String>("binding"))
                    require(binding.length in 1..512)
                    val aad = (context.packageName + ":" + binding).toByteArray(Charsets.UTF_8)
                    val tag = MessageDigest.getInstance("SHA-256").digest(aad)
                        .joinToString("") { "%02x".format(it.toInt() and 255) }
                    val file = AtomicFile(File(context.noBackupFilesDir, "common_session_$tag.bin"))
                    val alias = "common_session_v1_$tag"
                    when (call.method) {
                        "read" -> {
                            if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) result.success(null)
                            else {
                                val sealed = file.readFully()
                                require(sealed.size in 29..16384)
                                val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                                val key = keyStore.getKey(alias, null) as SecretKey
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed.copyOfRange(0, 12)))
                                cipher.updateAAD(aad)
                                result.success(String(cipher.doFinal(sealed.copyOfRange(12, sealed.size)), Charsets.UTF_8))
                            }
                        }
                        "write" -> {
                            val value = requireNotNull(call.argument<String>("value")).toByteArray(Charsets.UTF_8)
                            require(value.size in 1..8192)
                            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                            val key = if (keyStore.containsAlias(alias)) keyStore.getKey(alias, null) as SecretKey
                            else KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
                                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                                    .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
                                generateKey()
                            }
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key)
                            cipher.updateAAD(aad)
                            val bytes = cipher.iv + cipher.doFinal(value)
                            val output = file.startWrite()
                            try {
                                output.write(bytes)
                                file.finishWrite(output)
                            } catch (failure: Exception) {
                                file.failWrite(output)
                                throw failure
                            }
                            result.success(null)
                        }
                        "clear" -> {
                            file.delete()
                            require(!file.baseFile.exists())
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("session_store_failed", "Session storage unavailable", null)
                }
            }
    }
}
