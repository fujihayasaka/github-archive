# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Copilot
      class AdministrativeUnblockProcessor < SingleMessageProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-copilot-administrative_unblock_processor", String)
        DEFAULT_SUBSCRIBE_TO = /copilot\.v0\.CopilotAdministrativeUnblockRequest\Z/

        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.dead_letter_topic = "copilot.v0.CopilotAdministrativeUnblockRequest.DeadLetter"
        end

        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          unless FeatureFlag.vexi.enabled?(:copilot_administrative_unblock_processor, default: false)
            return message.skip("feature_flag_disabled")
          end
          return message.skip("ghes_not_supported") if GitHub.enterprise?

          payload = message.value
          user_id = payload[:user_id].to_i

          if user_id.zero?
            GitHub.logger.warn("Skipping Copilot administrative unblock request without user_id", log_context(payload))
            message.skip(:missing_user_id)
            return
          end

          user = ::User.find_by(id: user_id)
          if user.nil?
            GitHub.logger.warn("Skipping Copilot administrative unblock request for unknown user", log_context(payload))
            message.skip(:user_not_found)
            return
          end

          reason = "UNBLOCK: #{payload[:reason]} - no remedial email sent"
          actor = ::User.staff_user

          ::Copilot::User.new(user).administrative_unblock!(
            actor,
            reason,
            unblock_payment_method: !!payload[:unblock_payment_method],
          )

          # TODO: Send remediation email (fast-follow once deduplication strategy is in place)
          GitHub.logger.info("Processed Copilot administrative unblock request", log_context(payload))
        end

        private

        sig { params(payload: T::Hash[T.untyped, T.untyped]).returns(T::Hash[String, T.untyped]) }
        def log_context(payload)
          {
            "gh.copilot.administrative_unblock.user_id" => payload[:user_id],
            "gh.copilot.administrative_unblock.producer" => payload[:producer],
            "gh.copilot.administrative_unblock.request_id" => payload[:request_id],
          }
        end
      end
    end
  end
end
