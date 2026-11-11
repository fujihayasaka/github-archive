# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class PartnerMetadataService
      sig { params(repository: Repository, user: User, token_number: Integer).returns([T.nilable(SecretScanning::Models::PartnerTokenMetadata), T.nilable(StandardError)]) }
      def analyze_token(repository, user, token_number)
        response = GitHub::TokenScanning::Service::Client.new(user).get_token_metadata(
          GitHub::Proto::SecretScanning::Api::V2::GetTokenMetadataRequest.new(repository_id: repository.id, token_number: token_number, requested_by_user_id: user.id)
        )

        metadata = response&.data
        is_err, err = ServiceHelper.process_response(
          response: response,
          operation: "fetching partner token metadata",
          is_data_valid: metadata.present?,
          is_404_ok: false,
          failbot_attributes: {
            "gh.repo.id": repository.id,
            "gh.tss.alert.number": token_number,
          },
        )
        return nil, err if is_err || metadata.nil?

        [SecretScanning::Models::PartnerTokenMetadata.from_proto(metadata), nil]
      end

      sig do
        params(
          token: GitHub::TokenScanning::Service::Token,
          user: User,
        ).returns(
          [T.nilable(SecretScanning::Models::PartnerTokenMetadata), T.nilable(StandardError)]
        )
      end
      def self.refresh_token_metadata(token, user)
        req = GitHub::Proto::SecretScanning::Api::V2::RefreshTokenMetadataRequest.new(
          repository_id: token.repository_id,
          token_number: token.number,
          requested_by_user_id: user.id
        )
        response = GitHub::TokenScanning::Service::Client.new(user).refresh_token_metadata(req)
        response_data = response&.data
        is_err, err = ServiceHelper.process_response(
          response:,
          operation: "refreshing token metadata",
          is_data_valid: response_data.present?,
          is_404_ok: false,
          failbot_attributes: {
            "gh.repo.id": token.repository_id,
            "gh.user.id": user.id,
            "gh.tss.alert.number": token.number,
          },
        )
        return [nil, err] if is_err || response_data.nil?
        if token.is_github_token?
          SecretScanning::Encryption::EncryptedSecretsHelper.set_raw_secret_from_encrypted_secret(token)
          token.token.encrypted_metadata = response_data.encrypted_metadata
          return [SecretScanning::Models::PartnerTokenMetadata.build_from_token(token, repo: token.repository, user: user), nil]
        end
        [SecretScanning::Models::PartnerTokenMetadata.from_encrypted_proto(response_data.encrypted_metadata), nil]
      end
    end
  end
end
