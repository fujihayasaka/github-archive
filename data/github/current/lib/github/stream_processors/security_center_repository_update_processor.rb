# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class SecurityCenterRepositoryUpdateProcessor < SingleMessageProcessor
      DEFAULT_GROUP_ID = "security_center_repository_update_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.v1\.SecurityCenterRepositoryUpdate\Z/

      options[:min_bytes] = 1
      options[:max_wait_time] = 0.2.seconds
      options[:max_bytes_per_partition] = 1.megabyte
      options[:session_timeout] = 60.seconds
      options[:start_from_beginning] = false

      resolve_tenant_context do |message|
        repo_id = message.value[:repository_id]
        begin
          Repositories::Public.resolve_tenant(id: repo_id)
        rescue ActiveRecord::RecordNotFound
          GitHub.logger.error(
            "Failed to resolve tenant context.",
            "code.namespace": self.class.name&.underscore,
            "code.function": __method__,
            "gh.repo.id": repo_id,
            "gh.security_center.reason": "Repository not found.",
          )
          raise
        end
      end

      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

        self.metric_prefix = group_id
      end

      private

      def process_message(message)
        repo_id = message.value[:repository_id]
        feature_type = message.value[:feature_type]
        source_event = message.value[:source_event]

        GitHub.logger.with_named_tags(
          "gh.repo.id": repo_id,
          "gh.security_center.feature_type": feature_type,
          "gh.security_center.source_event": source_event,
        ) do
          # Trigger a job to do the actual update
          ::SecurityCenter::RepositorySyncJob.perform_later(
            repository_id: repo_id,
            feature_type: feature_type,
            source_event: source_event || "security_center.repository_update.unknown",
            event_timestamp: message.timestamp.to_f
          )

          GitHub.dogstats.increment("security_center.repository_update.processed", tags: ["feature_type:#{feature_type}", "source_event:#{source_event}"])
          GitHub.logger.info(
            "Message processed",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "messaging.source.name": message.topic,
            "messaging.kafka.source.partition": message.partition,
            "messaging.kafka.message.offset": message.offset,
          )
        end
      end
    end
  end
end
