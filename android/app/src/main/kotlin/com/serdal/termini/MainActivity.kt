package com.serdal.termini

import com.google.firebase.pnv.FirebasePhoneNumberVerification
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "checkmytime/pnv"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> handleIsSupported(result)
                "getVerifiedPhoneNumber" -> handleGetVerifiedPhoneNumber(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleIsSupported(result: MethodChannel.Result) {
        val fpnv = FirebasePhoneNumberVerification.getInstance()

        fpnv.getVerificationSupportInfo()
            .addOnSuccessListener { supportResults ->
                val supported = supportResults.any { supportResult ->
                    supportResult.isSupported()
                }
                result.success(supported)
            }
            .addOnFailureListener { exception ->
                result.error(
                    "PNV_SUPPORT_CHECK_FAILED",
                    exception.localizedMessage ?: "PNV support check failed.",
                    null
                )
            }
    }

    private fun handleGetVerifiedPhoneNumber(result: MethodChannel.Result) {
        val fpnv = FirebasePhoneNumberVerification.getInstance(this)

        fpnv.getVerifiedPhoneNumber()
            .addOnSuccessListener { verificationResult ->
                val phoneNumber = verificationResult.getPhoneNumber()
                val token = verificationResult.getToken()

                result.success(
                    mapOf(
                        "phoneNumber" to phoneNumber,
                        "token" to token
                    )
                )
            }
            .addOnFailureListener { exception ->
                result.error(
                    "PNV_VERIFICATION_FAILED",
                    exception.localizedMessage ?: "PNV verification failed.",
                    null
                )
            }
    }
}