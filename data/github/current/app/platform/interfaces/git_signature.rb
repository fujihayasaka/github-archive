# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module GitSignature
      include Platform::Interfaces::Base
      description "Information about a signature (GPG or S/MIME) on a Commit or Tag."

      field :email, String, method: :signer_email, description: "Email used to sign this object.", null: false

      field :signer, Objects::User, description: "GitHub user corresponding to the email signing this commit.", null: true

      def signer
        if @object.signer
          @context[:permission].typed_can_see?("User", @object.signer).then do |can_read|
            if can_read && !@object.signer.hide_from_user?(@context[:viewer])
              @object.signer
            end
          end
        end
      end

      field :signature, String, description: "ASCII-armored signature header from object.", null: false

      field :payload, String, description: "Payload for GPG signing object. Raw ODB object without the signature header.", null: false

      def payload
        payload = @object.signing_payload.dup
        # Make sure unicode characters are handled correctly
        payload.force_encoding(Encoding::UTF_8)
        payload
      end

      field :state, Enums::GitSignatureState,
        null: false,
        description: "The state of this signature. `VALID` if signature is valid and verified by GitHub, otherwise represents reason why signature is considered invalid.",
        method: :signature_verification_reason

      field :is_valid, Boolean,
        null: false,
        description: "True if the signature is valid and verified by GitHub.",
        method: :verified_signature?

      field :was_signed_by_git_hub, Boolean,
        null: false,
        description: "True if the signature was made with GitHub's signing key.",
        method: :signed_by_github?

      def self.resolve_type(object, context)
        case object
        when GitSigning::Verifiable::SshSignature
          Platform::Objects::SshSignature
        when GitSigning::Verifiable::GpgSignature
          Platform::Objects::GpgSignature
        when GitSigning::Verifiable::SmimeSignature
          Platform::Objects::SmimeSignature
        when GitSigning::Verifiable::UnknownSignature
          Platform::Objects::UnknownSignature
        end
      end
    end
  end
end
