package com.localpharmacy.app

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object SecureData {
    private const val keyAlias = "local-pharmacy-storage-v1"
    private const val version: Byte = 1
    private const val nonceLength = 12
    private const val tagBits = 128

    @Synchronized
    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        check(create) { "Encryption key is unavailable" }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    fun seal(plain: ByteArray, domain: String): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(create = true))
        check(cipher.iv.size == nonceLength)
        cipher.updateAAD(domain.toByteArray(Charsets.UTF_8))
        return byteArrayOf(version) + cipher.iv + cipher.doFinal(plain)
    }

    fun open(envelope: ByteArray, domain: String): ByteArray {
        require(envelope.size >= 1 + nonceLength + tagBits / 8 && envelope[0] == version)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(create = false),
            GCMParameterSpec(tagBits, envelope, 1, nonceLength),
        )
        cipher.updateAAD(domain.toByteArray(Charsets.UTF_8))
        val offset = 1 + nonceLength
        return cipher.doFinal(envelope, offset, envelope.size - offset)
    }
}
