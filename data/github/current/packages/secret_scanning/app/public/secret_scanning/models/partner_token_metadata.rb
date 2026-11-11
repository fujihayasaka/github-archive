# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class PartnerTokenMetadata < T::Struct
      class GitHubMetadataInfo < T::Struct
        const :link, T.nilable(String)
        const :owner, T.nilable(T::Hash[Symbol, T.untyped])
        const :is_owner_suspended, T.nilable(T::Boolean)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def serialize_ui
          {
            link:,
            owner:,
            is_owner_suspended:,
          }
        end
      end

      class MetadataPart < T::Struct
        const :key, String
        const :value, String

        sig do
          params(response: GitHub::Proto::SecretScanning::Api::V2::GetTokenMetadataResponse::TokenMetadata).returns(MetadataPart)
        end
        def self.from_proto(response)
          MetadataPart.new(key: response.key, value: response.value)
        end
      end

      # TODO: Delete these.
      # Deprecated: This isn't being consumed by clients.
      const :raw, T.nilable(String)
      # Deprecated: Old name that's redundant with the class name. Use kvps instead.
      const :metadata, T::Array[MetadataPart]

      const :secret_id, T.nilable(String)
      const :secret_name, T.nilable(String)
      const :owner_id, T.nilable(String)
      const :owner_name, T.nilable(String)
      const :owner_email, T.nilable(String)
      const :org_name, T.nilable(String)
      const :org_id, T.nilable(String)
      const :secret_issued_at, T.nilable(String)
      const :secret_expires_at, T.nilable(String)
      const :secret_last_used_at, T.nilable(String)
      const :org_access, T.nilable(String)
      const :kvps, T.nilable(T::Array[MetadataPart])
      prop :github_metadata, T.nilable(GitHubMetadataInfo)

      # Deprecated: We're using the decryption versions for stored metadata
      sig do
        params(response: GitHub::Proto::SecretScanning::Api::V2::GetTokenMetadataResponse).returns(PartnerTokenMetadata)
      end
      def self.from_proto(response)
        PartnerTokenMetadata.new(
          raw: response.raw,
          kvps: response.metadata.map { |md| MetadataPart.from_proto(md) },
          metadata: response.metadata.map { |md| MetadataPart.from_proto(md) },
        )
      end

      # Deprecated: Migrating to from_encrypted_proto
      sig do
        params(
          enc_metadata: T.nilable(String)
        ).returns(T.nilable(T::Array[{ key: String, value: String }]))
      end
      def self.decrypt_to_pairs(enc_metadata)
        return if enc_metadata.blank?
        decrypted_bytes = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.decrypt_encrypted_secret(enc_metadata)
        SecretScanning::Util::Protobuf.decode_metadata_parts(decrypted_bytes)
          .metadata.to_a.map { |part| { key: part.key, value: part.value } }
      end

      sig do
        params(
          token: GitHub::TokenScanning::Service::Token,
          repo: Repository,
          user: User,
        ).returns(T.nilable(PartnerTokenMetadata))
      end
      def self.build_from_token(token, repo:, user:)
        partner_metadata = from_encrypted_proto(token.encrypted_metadata)
        return if partner_metadata.nil?

        if token.is_github_token?
          github_token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)
          partner_metadata.github_metadata = build_github_metadata_info(github_token_metadata, partner_metadata, repo: repo, user: user)
        end

        partner_metadata
      end

      sig do
        params(
          enc_metadata: T.nilable(String)
        ).returns(T.nilable(PartnerTokenMetadata))
      end
      def self.from_encrypted_proto(enc_metadata)
        return if enc_metadata.blank?
        decrypted_bytes = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.decrypt_encrypted_secret(enc_metadata)
        decoded = SecretScanning::Util::Protobuf.decode_metadata_parts(decrypted_bytes)
        PartnerTokenMetadata.new(
          secret_id: decoded.secret_id.blank? ? nil : decoded.secret_id,
          secret_name: decoded.secret_name.blank? ? nil : decoded.secret_name,
          owner_id: decoded.owner_id.blank? ? nil : decoded.owner_id,
          owner_name: decoded.owner_name.blank? ? nil : decoded.owner_name,
          owner_email: decoded.owner_email.blank? ? nil : decoded.owner_email,
          org_name: decoded.org_name.blank? ? nil : decoded.org_name,
          org_id: decoded.org_id.blank? ? nil : decoded.org_id,
          secret_issued_at: decoded.secret_issued_at.blank? ? nil : decoded.secret_issued_at,
          secret_expires_at: decoded.secret_expires_at.blank? ? nil : decoded.secret_expires_at,
          secret_last_used_at: decoded.secret_last_used_at.blank? ? nil : decoded.secret_last_used_at,
          org_access: decoded.org_access.blank? ? nil : decoded.org_access,
          kvps: decoded.metadata.to_a.map { |part| MetadataPart.new(key: part.key, value: part.value) },
          metadata: decoded.metadata.to_a.map { |part| MetadataPart.new(key: part.key, value: part.value) },
        )
      end

      sig do
        params(
          current_token_metadata: T.nilable(SecretScanning::Models::GitHubTokenMetadata),
          stored_token_metadata: PartnerTokenMetadata,
          repo: Repository,
          user: User,
        ).returns(GitHubMetadataInfo)
      end
      def self.build_github_metadata_info(current_token_metadata, stored_token_metadata, repo:, user:)
        token_owner = User.find_by(id: stored_token_metadata.owner_id)
        owner = if token_owner
          SecretScanning::Models::React::BasePayloadBuilder.serialize_displayed_user(token_owner)
        end
        GitHubMetadataInfo.new(
          link: get_token_link(
            token_metadata: current_token_metadata,
            token_owner: token_owner,
            repo: repo,
            user: user,
          ),
          owner:,
          is_owner_suspended: token_owner.nil? ? false : token_owner.suspended?,
        )
      end

      sig do
        params(
          token_metadata: T.nilable(SecretScanning::Models::GitHubTokenMetadata),
          token_owner: T.nilable(User),
          repo: Repository,
          user: User,
        ).returns(T.nilable(String))
      end
      def self.get_token_link(token_metadata:, token_owner:, repo:, user:)
        return nil if token_metadata.nil?
        return nil if token_metadata.link.nil?

        if user.id == token_owner&.id
          return token_metadata.link
        end

        if token_metadata.token_type == "GITHUB_TOKEN_V2"
          return nil unless token_metadata.link.include?("organizations")
          repo_owner = repo.owner
          token_metadata.link if repo_owner.is_a?(::Organization) && SecurityProduct::Permissions::OrgAuthz.new(repo_owner, actor: user).can_manage_org_security_products?
        end
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def serialize_ui
        {
          owner_email:,
          secret_id:,
          secret_name:,
          owner_id:,
          owner_name:,
          org_name:,
          org_id:,
          secret_issued_at:,
          secret_expires_at:,
          secret_last_used_at:,
          org_access:,
          kvps: kvps&.map { |part| { key: part.key, value: part.value } },
          metadata: metadata.map { |part| { key: part.key, value: part.value } },
          github_metadata: github_metadata&.serialize_ui,
        }
      end
    end
  end
end
