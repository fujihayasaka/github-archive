# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Copilot
      class AgentSessionEventProcessor < SingleMessageProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-copilot-agent_session_event_processor"
        DEFAULT_SUBSCRIBE_TO = /copilot\.api\.v0\.CopilotApiAgentSession\Z/

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = false


        # Other options you may want to set...
        #
        # This will cause the Kafka consumer to wait until there is at least a
        # given number of bytes available to fetch; but the consumer will wait
        # no longer than "max_wait_time" (described below). This allows the
        # processor to wait for a large enough batch of data. The default is
        # 1 byte, meaning data will be fetched as soon as it's available. Value
        # below is for example purposes only and not a recommendation; the default
        # value of 1 should be suitable for most cases.
        # See https://kafka.apache.org/documentation/#fetch.min.bytes
        # options[:min_bytes] = 1.kilobyte
        #
        # This is the maximum amount of time the Kafka consumer will wait to
        # fetch data. The default is 500ms (0.5.seconds). Value below is for
        # example purposes only and not a recommendation; the default value of
        # 500ms should be suitable for most cases.
        # options[:max_wait_time] = 1.second
        #
        # This is the maximum amount of data that will be fetched at a time. This
        # value is specified in bytes, so the number of distinct Hydro messages
        # fetched depends on the size of those messages. The default is 1MB. You
        # may want to consider lowering this if processing each batch of messages
        # is taking more than 60 seconds in order to ensure that your processor
        # shuts down in a timely manner during deploys.
        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        # options[:max_bytes_per_partition] = 100.kilobytes

        resolve_tenant_context do |message|
          begin
            owner_id = message.value.dig(:owner_id, :value)
            raise "missing owner_id" if owner_id.nil?

            Organization.find(owner_id).business
          rescue ActiveRecord::RecordNotFound
            GitHub.logger.error(
              "Failed to resolve tenant context.",
              "gh.processor.name": self.class.name,
              "code.function": __method__,
              "gh.organization.id": message.value.dig(:owner_id, :value),
              "gh.processor.resolve_tenant.failure_reason": "Business not found.",
            )
            raise
          end
        end

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Processes an individual message from Hydro.
        #
        # This is the main hook that you must implement.
        #
        # For individual message processing (in a subclass of `SingleMessageProcessor`), this method will be called once
        # per consumer invocation. For batch message processing (in a subclass of `BatchedMessageProcessor`), the
        # default implementation of `process_batch` will call this method in a loop, once for each message in the batch
        # to be processed by a single consumer invocation.
        #
        # @param message - An individual GitHub::StreamProcessors::Message, which represents a Hydro event.
        #
        # @returns An arbitrary value that sub-classes may use for internal testing but that is ignored by this base
        #   class and all framework code in production.
        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          return unless FeatureFlag.vexi.enabled?(:copilot_agent_session_event_processor, default: false)
          Rails.logger.info("processing CopilotApiAgentSession event: #{message.value}")

          resource_type = message.value[:resource_type]

          if FeatureFlag.vexi.enabled?(:copilot_agent_session_event_processor_skip_blank_resource_type, default: false) && resource_type.blank?
            Rails.logger.info("skipping CopilotApiAgentSession event with blank resource_type, session_id=#{message.value[:session_id]}")
            message.skip(:blank_resource_type)
            return
          end

          user = user(message)
          return unless FeatureFlag.vexi.enabled?(:copilot_agent_session_event_processor_writes, user, default: false)

          # check if this is an existing record
          copilot_session_id = message.value[:session_id]
          raise "missing session_id" if copilot_session_id.nil?

          existing_session = ::Copilot::AgentSession.
            strict_loading.
            includes(:resource).
            find_by(copilot_session_id: copilot_session_id)

          if existing_session
            session_state = message.value[:session_state]
            update_args = if session_state == "completed"
              completed_at_seconds = message.value.dig(:completed_at, :seconds)
              completed_at = if completed_at_seconds
                Time.at(completed_at_seconds).utc
              else
                Time.now.utc
              end
              { state: session_state, updated_at: completed_at }
            else
              { state: message.value[:session_state] }
            end

            if existing_session.resource.nil?
              update_args[:resource] = resource(message, user: user)
            end

            with_write do
              existing_session.update!(**update_args)
            end

            return
          end

          repo = repository(message)
          resource = resource(message, user: user)

          # ignore user-owned repositories
          return unless repo.owner.organization?
          org = organization(message)
          business = org.business

          created_at_seconds = message.value.dig(:created_at, :seconds)
          created_at = if created_at_seconds
            Time.at(created_at_seconds).utc
          else
            Time.now.utc
          end

          agent_type = message.value[:agent_type]
          agent_id = message.dig(:agent_id, :value)

          if FeatureFlag.vexi.enabled?(:copilot_agent_session_event_processor_skip_invalid_agent, user, default: false)
            unless agent_type.present? && agent_id.present?
              Rails.logger.info("skipping CopilotApiAgentSession event with invalid agent data, " \
                "session_id=#{copilot_session_id}, agent_type=#{agent_type.inspect}, agent_id=#{agent_id.inspect}")
              message.skip(:invalid_agent_data)
              return
            end
          end

          with_write do
            ::Copilot::AgentSession.create!(
              business: business,
              organization: org,
              repository: repo,
              user: user,
              resource: resource,
              agent_id: agent_id,
              agent_type: agent_type,
              event_type: message.value[:event_type],
              copilot_session_id: copilot_session_id,
              name: message.value[:session_name],
              state: message.value[:session_state],
              created_at: created_at,
            )
          end
        end

        private

        def organization(message)
          owner_id = message.value.dig(:owner_id, :value)
          raise "missing owner_id" if owner_id.nil?

          Organization.find(owner_id)
        end

        def repository(message)
          repo_id = message.value.dig(:repo_id, :value)
          raise "missing repo_id" if repo_id.nil?

          Repositories::Public.get_active_or_deleted!(repo_id)
        end

        def user(message)
          user_id = message.value.dig(:user_id, :value)
          raise "missing user_id" if user_id.nil?

          User.find(user_id)
        end

        def resource(message, user: nil)
          resource_id = message.value.dig(:resource_id, :value)
          return nil unless resource_id.present?

          resource_type = message.value[:resource_type]
          case resource_type
          when "pull"
            PullRequest.find(resource_id)
          else
            raise "invalid resource_type (#{resource_type}) for resourced with ID='#{resource_id})'" unless resource_type == "pull"
          end
        end
      end
    end
  end
end
