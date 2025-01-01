# frozen_string_literal: true

require_relative "./service_client_base"

require "google/protobuf/well_known_types"

module Authnd
  module Client
    class SocialIdentityManager < ServiceClientBase
      def register_social_identity(provider, subject_id, user_id, user_email_id, headers: {})
        raise ArgumentError, "provider must be an integer (enum)" unless provider.is_a?(Integer)
        raise ArgumentError, "subject_id must be a string" unless subject_id.is_a?(String)
        raise ArgumentError, "user_id must be an integer" unless user_id.is_a?(Integer)
        raise ArgumentError, "user_email_id must be an integer" unless user_email_id.is_a?(Integer)

        request = Authnd::Proto::RegisterSocialIdentityRequest.new(
          provider: provider,
          subject_id: subject_id,
          user_id: user_id,
          user_email_id: user_email_id,
        )

        twirp_resp = @twirp_client.register_social_identity(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      def find_social_identity(provider, subject_id, user_email_id, headers: {})
        raise ArgumentError, "provider must be an integer (enum)" unless provider.is_a?(Integer)
        raise ArgumentError, "subject_id must be a string" unless subject_id.is_a?(String)
        raise ArgumentError, "user_email_id must be an integer" unless user_email_id.is_a?(Integer)

        request = Authnd::Proto::FindSocialIdentityRequest.new(
          provider: provider,
          subject_id: subject_id,
          user_email_id: user_email_id,
        )

        twirp_resp = @twirp_client.find_social_identity(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      def find_social_identities(user_id, headers: {})
        raise ArgumentError, "user_id must be an integer" unless user_id.is_a?(Integer)

        request = Authnd::Proto::FindSocialIdentitiesRequest.new(
          user_id: user_id,
        )

        twirp_resp = @twirp_client.find_social_identities(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      def delete_social_identity(user_email_id, headers: {})
        raise ArgumentError, "user_email_id must be an integer" unless user_email_id.is_a?(Integer)

        request = Authnd::Proto::DeleteSocialIdentityRequest.new(
          user_email_id: user_email_id,
        )

        twirp_resp = @twirp_client.delete_social_identity(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      def delete_social_identities(user_id, headers: {})
        raise ArgumentError, "user_id must be an integer" unless user_id.is_a?(Integer)

        request = Authnd::Proto::DeleteSocialIdentitiesRequest.new(
          user_id: user_id,
        )
        twirp_resp = @twirp_client.delete_social_identities(request, headers: headers)
        raise Authnd::Proto::Error.new(twirp_error: twirp_resp.error) if twirp_resp.error

        twirp_resp.data
      end

      def create_twirp_client(connection)
        Proto::SocialIdentityManagerClient.new(connection)
      end
    end
  end
end
