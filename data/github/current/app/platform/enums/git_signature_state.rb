# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class GitSignatureState < Platform::Enums::Base
      description "The state of a Git signature."

      value "VALID",                  "Valid signature and verified by GitHub",                                     value: "valid"
      value "INVALID",                "Invalid signature",                                                          value: "invalid"
      value "MALFORMED_SIG",          "Malformed signature",                                                        value: "malformed_signature"
      value "UNKNOWN_KEY",            "Key used for signing not known to GitHub",                                   value: "unknown_key"
      value "BAD_EMAIL",              "Invalid email used for signing",                                             value: "bad_email"
      value "UNVERIFIED_EMAIL",       "Email used for signing unverified on GitHub",                                value: "unverified_email"
      value "NO_USER",                "Email used for signing not known to GitHub",                                 value: "no_user"
      value "UNKNOWN_SIG_TYPE",       "Unknown signature type",                                                     value: "unknown_signature_type"
      value "UNSIGNED",               "Unsigned",                                                                   value: "unsigned"
      value "GPGVERIFY_UNAVAILABLE",  "Internal error - the GPG verification service is unavailable at the moment", value: "gpgverify_unavailable"
      value "GPGVERIFY_ERROR",        "Internal error - the GPG verification service misbehaved",                   value: "gpgverify_error"
      value "NOT_SIGNING_KEY",        "The usage flags for the key that signed this don't allow signing",           value: "not_signing_key"
      value "EXPIRED_KEY",            "Signing key expired",                                                        value: "expired_key"
      value "OCSP_PENDING",           "Valid signature, pending certificate revocation checking",                   value: "ocsp_pending"
      value "OCSP_ERROR",             "Valid signature, though certificate revocation check failed",                value: "ocsp_error"
      value "BAD_CERT",               "The signing certificate or its chain could not be verified",                 value: "bad_cert"
      value "OCSP_REVOKED",           "One or more certificates in chain has been revoked",                         value: "ocsp_revoked"
    end
  end
end
