# typed: true
# frozen_string_literal: true

module Commits
  # object that wraps a GitSigning::Verifiable to look like a GraphQL result
  class SignedCommitBadge
    def self.for(verifiable, current_user:)
      if verifiable.has_signature?
        new(verifiable, current_user: current_user)
      else
        nil
      end
    end

    def initialize(verifiable, current_user:)
      @verifiable = verifiable
      @current_user = current_user
    end

    def verification_status
      @verifiable.verification_status&.downcase&.to_sym
    end

    def is_valid?
      @verifiable.verified_signature?
    end

    def verified_at
      @verifiable.signature_verified_at if @current_user&.feature_enabled?(:signature_verified_at)
    end

    def signed_by_github?
      @verifiable.signed_by_github?
    end

    class Signer
      def initialize(user, current_user:)
        @user = user
        @current_user = current_user
      end

      def display_login
        @user.display_login
      end

      def name
        @user.profile_name
      end

      def avatar_url
        @user.primary_avatar_url(64)
      end

      def is_viewer?
        @user == @current_user
      end
    end

    def signer
      # TODO return nil if signer.hide_from_user?(current_user)
      if @verifiable.signer
        Signer.new(@verifiable.signer, current_user: @current_user)
      end
    end

    def typename
      if @verifiable.gpg_signature?
        "GpgSignature"
      elsif @verifiable.smime_signature?
        "SmimeSignature"
      elsif @verifiable.ssh_signature?
        "SshSignature"
      end
    end

    # The GPGKey that generated the signature.
    # nil if the signature is not gpg.
    def signing_gpg_key
      if !defined? @signing_gpg_key
        @signing_gpg_key = @verifiable.gpg_signature? ? @verifiable.signer.gpg_keys.find_by_key_id(@verifiable.signature_issuer_key_id) : nil
      end
      @signing_gpg_key
    end

    def expired?
      signing_gpg_key&.expired?
    end

    def revoked?
      signing_gpg_key&.revoked?
    end

    def key_id
      @verifiable.signature_issuer_key_id_hex
    end

    def key_fingerprint
      @verifiable.ssh_key_fingerprint_hex
    end

    def state
      Platform::Enums::GitSignatureState.coerce_isolated_result(@verifiable.signature_verification_reason)
    end

    class CertificateAttributes
      def initialize(certificate_attributes)
        @certificate_attributes = certificate_attributes || {}
      end

      def common_name
        @certificate_attributes["CN"]
      end

      def email_address
        @certificate_attributes["emailAddress"]
      end

      def organization
        @certificate_attributes["O"]
      end

      def organization_unit
        @certificate_attributes["OU"]
      end
    end

    def subject
      CertificateAttributes.new(@verifiable.signature_certificate_subject)
    end

    def issuer
      CertificateAttributes.new(@verifiable.signature_certificate_issuer)
    end
  end
end
