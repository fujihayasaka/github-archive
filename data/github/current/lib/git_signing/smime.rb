# typed: true
# frozen_string_literal: true

module GitSigning
  module SMIME
    include Kernel

    SIGNATURE_PREFIX = "-----BEGIN SIGNED MESSAGE-----"
    SIGNATURE_SUFFIX = "-----END SIGNED MESSAGE-----"

    # Is this an S/MIME signature?
    #
    # sig - A String that might be an S/MIME signature.
    #
    # Returns boolean.
    def signature?(sig)
      if sig
        parse_signature(sig)
        true
      else
        false
      end
    rescue GitSigning::InvalidSignatureError
      false
    end

    # Verify a set of messages/signatures.
    #
    # requests - An Array of request Hashes.
    #            :message   - The String message.
    #            :signature - The String signature.
    #            :email     - The email of the User that allegedly signed the
    #                         message.
    #            :user      - The User associated with the email address.
    #            :id        - A unique String to identify this Hash.
    #
    # Returns request Hashes, updated to include :valid and :reason keys, plus
    # other metadata.
    def verify_signatures(requests)
      requests.each do |req|
        req[:pkcs7] = parse_signature(req[:signature])
        req[:signer_cert], other_certs = certs_from_pkcs7(req[:pkcs7])

        # Skip the rest of this block if the request is already marked valid; just needed the above info added
        next if req[:already_verified]

        # There should be exactly one signature in the CMS SignedData object.
        # The spec allows for multiple, but many tools disallow this. This
        # shouldn't happen in practice, so we disallow it.
        if req[:pkcs7].signers.length > 1 || req[:signer_cert].nil?
          req[:reason] = GitSigning::INVALID
          req[:valid] = false
          next
        end

        # Flags for modifying the PKCS7 verification behavior.
        # https://www.openssl.org/docs/man1.0.2/crypto/PKCS7_verify.html
        flags = 0

        # The NOVERIFY flag specifies that chain verification shouldn't be
        # performed. We're doing this ourselves later so we can differentiate
        # between a bad signature and a bad cert chain and provide the user with
        # a better error message.
        flags |= OpenSSL::PKCS7::NOVERIFY

        # The NOINTERN flags specifies that the certificates in the signature
        # shouldn't be searched when looking for the signer's certificate. The
        # Array of certs we pass will be searched instead. This just gives us
        # greater assurance that we'll be verifying the chain on the correct
        # certificate down below.
        flags |= OpenSSL::PKCS7::NOINTERN

        # Is actual signature valid?
        unless req[:pkcs7].verify([req[:signer_cert]], cert_store, req[:message], flags)
          req[:reason] = GitSigning::INVALID
          req[:valid] = false
          next
        end

        # Are the certificate and its chain valid?
        if !cert_store.verify(req[:signer_cert], other_certs) || cert_store.chain.nil?
          req[:reason] = GitSigning::BAD_CERT
          req[:valid] = false
          next
        end

        # Does the signer certificate include the committer/tagger email?
        unless emails_from_certificate(req[:signer_cert]).include?(req[:email])
          req[:reason] = GitSigning::BAD_EMAIL
          req[:valid] = false
          next
        end

        case GitHub::OCSP.check_async(cert_store.chain)
        when GitHub::OCSP::OK
          req[:reason] = GitSigning::VALID
          req[:valid] = true
        when GitHub::OCSP::PENDING
          req[:reason] = GitSigning::OCSP_PENDING
          req[:valid] = true
        when GitHub::OCSP::ERROR
          req[:reason] = GitSigning::OCSP_ERROR
          req[:valid] = false
        when GitHub::OCSP::REVOKED
          req[:reason] = GitSigning::OCSP_REVOKED
          req[:valid] = false
        end
      end

      requests
    end

    # Extract signer certificate from PKCS7 object.
    #
    # p7 - An OpenSSL::PKCS7 instanace.
    #
    # Returns an Array on success. The first elelemnt is the signer's
    # certificate. The second element is an Array of intermediate certs.
    def certs_from_pkcs7(p7)
      signer = p7.signers.first

      # The certificates field in the CMS SignedData is optional. OpenSSL gives
      # us nil instead of an empty Array if it was ommitted.
      certs = p7.certificates || []

      signer_certs, other_certs = certs.partition do |cert|
        signer.issuer == cert.issuer && signer.serial == cert.serial
      end

      [signer_certs.first, other_certs]
    end

    # Parses email addresses from the cert in a signature.
    #
    # sig  - A S/MIME encoded signature String or an OpenSSL::PKCS7 object.
    #
    # Returns an Array of email address Strings.
    def emails_from_certificate(cert)
      emails_from_san(cert) + emails_from_subject(cert)
    end

    # Parses email addresses from the subject of a certificate.
    #
    # cert - An OpenSSL::X509::Certificate.
    #
    # Returns an Array of email address Strings.
    def emails_from_subject(cert)
      subject = cert.subject.to_a.map { |k, v, _| [k, v] }.to_h
      [subject["CN"], subject["emailAddress"]].select { |e| e && e["@"] }
    end

    # Parses email addresses from the SAN of a certificate.
    #
    # cert - An OpenSSL::X509::Certificate.
    #
    # Returns an Array of email address Strings.
    def emails_from_san(cert)
      san_extensions = cert.extensions.select do |ext|
        ext.oid == "subjectAltName"
      end
      emails = san_extensions.collect do |ext|
        # `subjectAltName` contains one or more values in a ASN1 sequence that we need
        # to decode. The result value of the sequence is an array of subject
        # alternative tag/values.
        sans = OpenSSL::ASN1.decode(ext.value_der).value
        sans
          # rfc822Name==1 in GeneralName (RFC5280)
          .select { |san| san.tag == 1 }
          .collect { |san| san.value }
      end
      # If there were multiple subjectAltName extensions then we will have an
      # array of array of values. We want to flatten that to a simple array of
      # emails.
      emails.flatten
    end

    # Parses a S/MIME signature.
    #
    # sig - A S/MIME encoded signature String.
    #
    # Returns a OpenSSL::PKCS7 instnace. Raises InvalidSignatureError if the
    # signature cannot be parsed.
    def parse_signature(sig)
      lines = sig.split("\n")

      unless SIGNATURE_PREFIX == lines.shift
        raise GitSigning::InvalidSignatureError, "missing header"
      end

      unless SIGNATURE_SUFFIX == lines.pop
        raise GitSigning::InvalidSignatureError, "missing footer"
      end

      bytes = begin
        Base64.strict_decode64(lines.join)
      rescue ArgumentError
        raise GitSigning::InvalidSignatureError, "invalid base64"
      end

      p7 = begin
        OpenSSL::PKCS7.new(bytes)
      rescue ArgumentError
        raise GitSigning::InvalidSignatureError, "invalid pkcs7 data"
      end

      p7
    end

    def cert_store
      GitHub.git_signing_smime_cert_store
    end

    extend self
  end
end
