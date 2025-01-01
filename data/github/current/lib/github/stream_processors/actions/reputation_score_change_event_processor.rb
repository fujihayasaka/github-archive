# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Actions
      class ReputationScoreChangeEventProcessor < BaseProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "actions_reputation_score_change_event_processor"
        DEFAULT_SUBSCRIBE_TO = /github\.actions\.v0\.ReputationScoreChange\Z/

        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds
        # starts up, i.e. on every deploy.
        options[:start_from_beginning] = false

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          return message.skip("ghes_not_supported") if GitHub.enterprise?
          reputation_score = message.value.dig(:reputation_score)
          return message.skip("non_zero_reputation_score") unless reputation_score == 0

          type = message.value.dig(:billing_plan_owner, :type)
          global_id = message.value.dig(:billing_plan_owner, :global_id)
          begin
            entity_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)[1]
          rescue Platform::Errors::NotFound
            entity_id = nil
          end


          return message.skip("message_malformed") if global_id.nil? || entity_id.nil?

          if type == :TYPE_USER
            entity = User.find_by(id: entity_id)
          elsif type == :TYPE_ORGANIZATION
            entity = Organization.find_by(id: entity_id)
          elsif type == :TYPE_BUSINESS
            entity = Business.find_by(id: entity_id)
          else
            # We don't expect other :billing_plan_owner types, but they are possible per the
            # hydro/schemas/github/actions/v0/billing_plan_owner.proto, so if we happen to get
            # them, we should skip and take no action
            return message.skip("unhandled_billing_type")
          end

          return message.skip("entity_does_not_exist") if entity.nil?

          return message.skip("already_blocked") if entity.action_invocation_blocked?
          return message.skip("already_spammy") if entity.spammy?

          blocking_user = GitHub.launch_github_app.bot

          ::Actions::Invocation.block(actor: entity, staff_actor: blocking_user)
          GitHub.logger.info("Processed ReputationScoreChangeEvent", {
            "code.namespace" => self.class.name,
            "code.function" => "process_message",
            "gh.actions.actor.global_id" => global_id,
          })
        end
      end
    end
  end
end
