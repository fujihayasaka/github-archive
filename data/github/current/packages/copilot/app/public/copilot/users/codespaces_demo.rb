# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module CodespacesDemo
      extend T::Helpers

      include Copilot::Users::Signatures

      abstract!

      sig { override.returns(T::Boolean) }
      def codespaces_demo_request_allowed?
        return false unless installation = user_object.oauth_access&.installation
        return false unless installation.is_a?(SiteScopedIntegrationInstallation)
        return false unless codespace_id = installation.codespace_ids.first
        return false unless codespace = Codespace.find_by(id: codespace_id)
        # check the repo
        codespaces_demo_usage_allowed?(codespace)
      end

      sig { override.params(codespace: Codespace).returns(T::Boolean) }
      def codespaces_demo_usage_allowed?(codespace)
        return false unless repository = codespace.repository
        GitHub.flipper[:codespaces_copilot_demo_repository].enabled?(T.cast(repository, Repository)) # rubocop:todo GitHub/AvoidCast
      end

      sig { override.returns(T::Boolean) }
      def codespaces_demo_session_active?
        codespaces_demo_session_value != CODESPACES_DEMO_FINAL_VALUE
      end

      sig { override.void }
      def increment_codespaces_demo_session_value!
        GitHub.logger.info(
          "Loading Codespaces demo session value",
          {
            "gh.user.id" => user_object.id,
            "gh.copilot.codespaces_demo_session_value" => codespaces_demo_session_value.to_s,
          }
        )

        case codespaces_demo_session_value
        when nil
          # if the cached value is nil, this is the first time the user has phoned home (0 minutes)
          update(CODESPACES_DEMO_FIRST_VALUE)
        when CODESPACES_DEMO_FIRST_VALUE
          # if the cached value is FIRST_VALUE, this is the second time the user has phoned home (30 minutes)
          update(CODESPACES_DEMO_SECOND_VALUE)
        when CODESPACES_DEMO_SECOND_VALUE
          # if the cached value is SECOND_VALUE, this is the third time the user has phoned home (60 minutes)
          update(CODESPACES_DEMO_THIRD_VALUE)
        when CODESPACES_DEMO_THIRD_VALUE
          # if the cached value is THIRD_VALUE, this is the fourth time the user has phoned home (90 minutes)
          update(CODESPACES_DEMO_FOURTH_VALUE)
        when CODESPACES_DEMO_FOURTH_VALUE
          update(CODESPACES_DEMO_FINAL_VALUE)
        else
          # if the cached value is anything else, this is the fifth or later time the user has phoned home (120+ minutes)
        end
      end

      sig { override.returns(String) }
      def codespaces_demo_key
        "copilot:codespaces_demo:#{user_object.id}"
      end

      sig { override.returns(T.nilable(String)) }
      def codespaces_demo_session_value
        # originally i had this on the write connection, but realistically, there is supposed to be 30 minutes between
        # requests and i think there will be at least a few seconds between requests so replication should happen
        # worst case scenario if i'm wrong?  we give the user a little extra time
        Copilot::Helpers.with_read do
          Copilot.redis.get(codespaces_demo_key)
        end
      end

      private

      sig { params(value: String).void }
      def update(value)
        GitHub.logger.info(
          "Updating codespaces demo session value",
          {
            "gh.user.id" => user_object.id,
            "gh.copilot.updated_codespaces_demo_session_value" => value
          }
        )
        Copilot::Helpers.with_write do
          Copilot.redis.set(codespaces_demo_key, value, ex: 30.minutes.to_i)
        end
      end
    end
  end
end
