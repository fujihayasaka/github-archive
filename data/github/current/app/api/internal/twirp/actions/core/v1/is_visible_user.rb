# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class IsVisibleUser
        include Api::Internal::Twirp::Actions::Core::V1::ArgumentsDependency

        attr_reader :req, :env

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: req.user_id)
          get_user_visibility_status(user)
        end

        private

        # Private: Checks if the given user is visible.
        #
        # user - the User whose visibility should be checked
        #
        # Returns a Hash suitable for use as a MonolithTwirp::Actions::Core::V1::IsVisibleUserResponse.
        def get_user_visibility_status(user)
          if user.nil?
            { is_visible: false, reason: :REASON_DELETED }
          elsif user.suspended?
            { is_visible: false, reason: :REASON_SUSPENDED }
          elsif GitHub.spamminess_check_enabled? && user.spammy?
            { is_visible: false, reason: :REASON_SPAMMY }
          else
            { is_visible: true }
          end
        end
      end
    end
  end
end
