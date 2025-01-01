# typed: true
# frozen_string_literal: true

module GitSigning
  module SSH
    include Kernel

    SIGNATURE_PREFIX = "-----BEGIN SSH SIGNATURE-----"
    SIGNATURE_SUFFIX = "-----END SSH SIGNATURE-----"

    def signature?(sig)
      return false unless sig
      return false unless parse_signature(sig)
      true
    rescue GitSigning::InvalidSignatureError
      false
    end

    def parse_signature(sig)
      begin
        SSHData::Signature.parse_pem(sig)
      rescue SSHData::Error
        raise GitSigning::InvalidSignatureError, "invalid signature data"
      end
    end

    def verify_signatures(requests)
      return requests if requests.empty?

      # Parse each signature and gather a list of all fingerprints
      requests.each do |req|
        begin
          req[:ssh_signature] = SSHData::Signature.parse_pem(req[:signature])
        rescue SSHData::Error
          req[:ssh_signature] = nil
        end

        # return early if the commit is already verified
        next if req[:already_verified]

        user = req[:user]

        # Couldn't parse the signature, or the namespace is not 'git'.
        # SSH signatures for git commit signing must have a namespace of 'git'.
        if req[:ssh_signature].nil? || req[:ssh_signature].namespace != "git"
          req[:reason] = GitSigning::MALFORMED_SIG
          req[:valid] = false
          next
        end

        # The signature didn't verify.
        # We don't require user presence for SSH signatures because by default git doesn't require them either,
        # even without explicitly indicating no-touch-required anywhere.
        begin
          if !req[:ssh_signature].verify(req[:message], user_presence_required: false)
            req[:reason] = GitSigning::INVALID
            req[:valid] = false
            next
          end
        rescue SSHData::Error, ArgumentError
          req[:reason] = GitSigning::MALFORMED_SIG
          req[:valid] = false
          next
        end

        if req[:ssh_signature].public_key.is_a?(SSHData::Certificate)
          req[:reason] = GitSigning::UNKNOWN_SIG_TYPE
          req[:valid] = false
          next
        end

        # The user is assigned to this request in GitSigning.verify_signatures.
        # That method looks up the user by the email of this tag/commit's signer
        fingerprint = req[:ssh_signature].public_key.fingerprint
        if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
          fingerprint = fingerprint << "_#{current_tenant.shortcode}"
        end
        user_key = user.git_signing_ssh_public_keys.find_by(fingerprint_sha256: fingerprint)

        # Public key does not belong to the user.
        if user_key.blank?
          req[:reason] = GitSigning::UNKNOWN_KEY
          req[:valid] = false
          next
        end

        req[:reason] = GitSigning::VALID
        req[:valid] = true
      end

      requests
    end

    extend self
  end
end
