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
            "repo.id": repository.id,
            "token_number": token_number,
          },
        )
        return nil, err if is_err || metadata.nil?


        [SecretScanning::Models::PartnerTokenMetadata.from_proto(metadata), nil]
      end

    end
  end
end
