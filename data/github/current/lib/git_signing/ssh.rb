# typed: false
# frozen_string_literal: true

module GitSigning
  module SSH
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
      requests.each do |request|
        ssh_signature = nil

        begin
          ssh_signature = SSHData::Signature.parse_pem(request[:signature])
        rescue SSHData::Error
          ssh_signature = nil
        end

        user = request[:user]

        # Couldn't parse the signature, or the namespace is not 'git'.
        # SSH signatures for git commit signing must have a namespace of 'git'.
        if ssh_signature.nil? || ssh_signature.namespace != "git"
          request[:reason] = GitSigning::MALFORMED_SIG
          request[:valid] = false
          next
        end

        # The signature didn't verify.
        # We don't require user presence for SSH signatures because by default git doesn't require them either,
        # even without explicitly indicating no-touch-required anywhere.
        begin
          if !ssh_signature.verify(request[:message], user_presence_required: false)
            request[:reason] = GitSigning::INVALID
            request[:valid] = false
            next
          end
        rescue SSHData::Error, ArgumentError
          request[:reason] = GitSigning::MALFORMED_SIG
          request[:valid] = false
          next
        end

        if ssh_signature.public_key.is_a?(SSHData::Certificate)
          request[:reason] = GitSigning::UNKNOWN_SIG_TYPE
          request[:valid] = false
          next
        end

        # The signature is valid, so we can say that it is valid for the commit. We don't
        # know if it is trustworthy at this point.
        request[:ssh_signature] = ssh_signature

        # The user is assigned to this request in GitSigning.verify_signatures.
        # That method looks up the user by the email of this tag/commit's signer
        fingerprint = ssh_signature.public_key.fingerprint
        if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
          fingerprint = fingerprint << "_#{current_tenant.shortcode}"
        end
        user_key = user.git_signing_ssh_public_keys.find_by(fingerprint_sha256: fingerprint)

        # Public key does not belong to the user.
        if user_key.blank?
          request[:reason] = GitSigning::UNKNOWN_KEY
          request[:valid] = false
          next
        end

        request[:reason] = GitSigning::VALID
        request[:valid] = true
      end

      requests
    end

    extend self
  end
end
