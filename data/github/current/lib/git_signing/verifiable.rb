# typed: false
# frozen_string_literal: true

module GitSigning::Verifiable
  extend T::Helpers

  class Signature
    include GitHub::Relay::GlobalIdentification

    attr_reader :verifiable

    def initialize(verifiable)
      @verifiable = verifiable
    end

    delegate :signer_email,
             :signer,
             :signature,
             :signing_payload,
             :signature_verification_reason,
             :verified_signature?,
             :signature_verified_at,
             :signature_certificate_issuer,
             :signature_certificate_subject,
             :signature_issuer_key_id_hex,
             :signature_verification_data,
             :repository,
             :signed_by_github?,
             :ssh_key_fingerprint_hex,
             to: :verifiable
  end

  class GpgSignature < Signature
  end

  class SmimeSignature < Signature
  end

  class SshSignature < Signature
  end

  class UnknownSignature < Signature
  end

  module ClassMethods
    # Read signatures and signing payloads from GitRPC for a group of objects.
    #
    # repo - The Repository all the commits belong to.
    # oids - An Array of String object OIDs.
    #
    # Returns an Array of Arrays. The first element of each array is the
    # signature and the second element is the signing payload.
    def parse_signing_data(objects)
      raise NotImplementedError
    end

    # Load signed object data for a group of objects.
    #
    # objects       - An Array of object objects.
    # fallback_repo - A Repository or RepositoryNetwork to use for RPC if an
    #                 object isn't associated with a repo (Eg. A deleted fork).
    #
    # Returns nothing.
    def prefill_signing_data(objects, fallback_repo = nil)
      return if objects.empty?

      # Skip objects whose signing data has already been loaded.
      objects = objects.reject(&:signing_data_loaded?)

      # Skip unsigned objects.
      objects = objects.reject do |object|
        unless object.has_signature?
          nil_signing_data!(object)
          true
        end
      end

      objects.group_by(&:repository).each do |repo, repo_objects|
        repo ||= fallback_repo

        if repo.nil?
          nil_signing_data!(repo_objects)
          next
        end

        oids = repo_objects.map(&:oid)

        signing_data = begin
          parse_signing_data(repo, oids)
        rescue GitRPC::ObjectMissing
          nil_signing_data!(repo_objects)
          next
        end

        should_capture_commit_date = FeatureFlag.vexi.enabled?(:gpg_verify_inject_additional_telemetry, default: true)

        repo_objects.zip(signing_data).each do |object, (signature, payload)|
          object.signature_verification_data.merge!(
            signature: !signature.blank? ? signature : nil,
            message: !payload.blank? ? payload : nil,

            # Prefill network_id for AuthenticCommit processing
            network_id: repo.network_id,

            # Pre fill business for EMU email processing
            business: repo.async_enterprise_managed_business.sync
          )

          if should_capture_commit_date
            object.signature_verification_data.merge!(
              commit_date: object.created_at ? object.created_at.utc : nil,
              repository_id: repo&.id,
              repository_nwo: repo&.name_with_display_owner,
              owner: repo&.owner&.display_login
            )
          end
        end
      end
    end

    # Adds a nil signature and message to some Git objects.
    #
    # objects - A Commit/Tag object or an Array of Commit/Tag objects.
    #
    # Returns nothing.
    def nil_signing_data!(objects)
      Array(objects).each do |object|
        object.signature_verification_data.merge!(
          signature: nil,
          message: nil,
        )
      end
    end

    # Load object signature verification results for a group of objects.
    #
    # objects - An Array of objects that respond to `#has_signature?`,
    #           `#signature_issuer_key_id`, `#signer_email`, `#signature`,
    #           `#signing_payload`, and `#oid`.
    # repo    - A Repository or RepositoryNetwork to use for RPC, since
    #           Commit#repository can be nil.
    # save_to_db - If true, verified statuses will be saved to the AuthenticCommit table. This should only be
    #              false if it's possible the commits may not ultimately be accepted by our servers after this
    #              check runs.
    #
    # Returns nothing.
    def prefill_verified_signature(objects, repo = nil, save_to_db: true)
      prefill_signing_data(objects, repo)

      start_time = GitHub::Dogstats.monotonic_time
      GitSigning.verify_signatures(objects.map(&:signature_verification_data), save_to_db:)
      elapsed_ms = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("git_signing.verify_signatures.duration", elapsed_ms)
    end
  end

  # Is there a signature header on this object? This does not indicate that the
  # signature is trusted or has been verified.
  #
  # Returns boolean.
  def has_signature?
    !!@has_signature
  end

  # A verification request to be sent to GitSigning.verify_signatures. This Hash
  # is updated by prefill_signing_data to include :message and :signature keys.
  # It is updated by prefill_verified_signature to include :valid and :reason
  # keys.
  #
  # Returns a Hash.
  def signature_verification_data
    @signature_verification_data ||= {
      email: signer_email,
      id: oid,
    }
  end

  # Payload for GPG signing object.
  #
  # Returns raw ODB object String minus the `gpgsig` header.
  def signing_payload
    ensure_signing_data_loaded
    signature_verification_data[:message]
  end

  # Signature header from object.
  #
  # Returns ASCCI armored signature String (`gpgsig` header) or nil.
  def signature
    ensure_signing_data_loaded
    signature_verification_data[:signature]
  end

  def signature_object
    ensure_signature_checked
    case signature_verification_data[:class]
    when GitSigning::GPG
      GpgSignature.new(self)
    when GitSigning::SMIME
      SmimeSignature.new(self)
    when GitSigning::SSH
      SshSignature.new(self)
    else
      UnknownSignature.new(self)
    end
  end

  # Get the id of the key that signed this object.
  #
  # Returns a binary String.
  def signature_issuer_key_id
    ensure_signature_checked
    signature_verification_data[:key_id]
  end

  # Hex representation of the signature issuer's GPG key-id.
  #
  # Returns a String or nil.
  def signature_issuer_key_id_hex
    GpgKey.hex_key_id(signature_issuer_key_id) if signature_issuer_key_id
  end

  def ssh_key_fingerprint_hex
    ensure_signature_checked
    return nil unless verified_signature?
    signature_verification_data[:ssh_signature]&.public_key&.fingerprint
  end

  # The "subject" from the S/MIME signature certificate.
  #
  # Returns a Hash of Subject fields.
  def signature_certificate_subject
    return @signature_certificate_subject if defined?(@signature_certificate_subject)
    ensure_signature_checked
    cert = signature_verification_data[:signer_cert]

    @signature_certificate_subject = if cert
      get_dn_components(cert.subject)
    end
  end

  # The "issuer" from the S/MIME signature certificate.
  #
  # Returns a Hash of issuer fields.
  def signature_certificate_issuer
    return @signature_certificate_issuer if defined?(@signature_certificate_issuer)
    ensure_signature_checked
    cert = signature_verification_data[:signer_cert]

    @signature_certificate_issuer = if cert
      get_dn_components(cert.issuer)
    end
  end

  # Was this object signed by it's author/committer?
  #
  # Returns boolean.
  def verified_signature?
    ensure_signature_checked
    signature_verification_data[:valid]
  end

  # Returns the Time this object's signature was verified at, or nil if it was not verified.
  def signature_verified_at
    ensure_signature_checked
    signature_verification_data[:verified_at]
  end

  # Was this object signed by a user other than it's author/committer?
  #
  # Returns boolean.
  def unverified_signature?
    has_signature? && !verified_signature?
  end

  # The reason why the signature is invalid. This corresponds to one of the
  # constants defined in GitSigning.
  #
  # Returns a String.
  def signature_verification_reason
    ensure_signature_checked
    signature_verification_data[:reason]
  end

  # Does this object have a GPG signature?
  #
  # Returns boolean.
  def gpg_signature?
    if has_signature?
      ensure_signature_checked
      signature_verification_data[:class] == GitSigning::GPG
    else
      false
    end
  end

  # Does this object have an S/MIME signature?
  #
  # Returns boolean.
  def smime_signature?
    if has_signature?
      ensure_signature_checked
      signature_verification_data[:class] == GitSigning::SMIME
    else
      false
    end
  end

  def ssh_signature?
    if has_signature?
      ensure_signature_checked
      signature_verification_data[:class] == GitSigning::SSH
    else
      false
    end
  end

  # User whose committer/author email was in the object.
  #
  # Returns a User instance or nil.
  def signer
    ensure_signature_checked
    signature_verification_data[:user]
  end

  # Tries to validate the signature if it hasn't been done already.
  #
  # Returns nothing.
  def ensure_signature_checked
    self.class.prefill_verified_signature([self], repository) unless signature_checked?
  end

  # Has the signature in this object been checked for validity by
  # GitSigning.verify_signatures yet?
  #
  # Returns boolean.
  def signature_checked?
    [:valid, :reason].all? { |k| signature_verification_data.key?(k) }
  end

  # Loads the signature and signing payload if they haven't been loaded already.
  #
  # Returns nothing.
  def ensure_signing_data_loaded
    self.class.prefill_signing_data([self], repository) unless signing_data_loaded?
  end

  # Has the signature/payload already been loaded?
  #
  # Returns boolean.
  def signing_data_loaded?
    [:signature, :message].all? { |k| signature_verification_data.key?(k) }
  end

  # Was this commit/tag made in the web-UI and signed by GitHub's key?
  #
  # Returns boolean.
  def signed_by_github?
    signer_email == GitHub.web_committer_email
  end

  mixes_in_class_methods(GitSigning::Verifiable::ClassMethods)

  private

  def get_dn_components(distinguished_name)
    components = distinguished_name.to_a.map do |component, value, type|
      value_converted = case type
      when OpenSSL::ASN1::UTF8STRING
        # The encoding said it's UTF-8, so treat it as UTF-8.
        value.dup.force_encoding("utf-8")
      when OpenSSL::ASN1::BMPSTRING
        # The encoding said it's a BMPString. Text rendering may not understand
        # UTF-16 BE, so convert it to UTF8.
        value.dup.force_encoding("utf-16be").encode("utf-8")
      else
        value
      end

      # If we don't believe the component is correctly encoded, skip over it.
      next unless value_converted.valid_encoding?

      [component, value_converted]
    end

    components.to_h
  end
end
