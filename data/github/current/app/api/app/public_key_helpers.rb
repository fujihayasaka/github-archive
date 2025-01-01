# typed: true
# frozen_string_literal: true

module Api
  class App
    module PublicKeyHelpers
      include Api::App::ErrorDependency
      BLOCKED_USER_AGENTS = [
        # https://github.com/github/security/issues/4403
        "GitKraken/7.6", # All of 7.6.x
        "GitKraken/7.7", # All of 7.7.x
        "GitKraken/8.0.0"
      ].freeze

      def deliver_user_agent_blocked_error!
        deliver_error! 403, message: "This application is not permitted to perform this operation."
      end

      def user_agent_blocked_from_adding_pubkey?(user_agent)
        BLOCKED_USER_AGENTS.any? do |ua|
          user_agent.include? ua
        end
      end
    end
  end
end
