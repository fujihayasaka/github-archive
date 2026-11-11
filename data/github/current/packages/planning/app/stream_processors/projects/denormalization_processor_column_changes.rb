# typed: strict
# frozen_string_literal: true

require "github/stream_processors/transient_error_resiliency_helpers"

module Projects
  # This processor handles column-change topics split out from the main DenormalizationProcessor
  # to reduce blast radius and allow independent scaling.
  #
  # It handles the following topics:
  #   - github.memex.v0.MemexProjectColumnValueCreate
  #   - github.memex.v0.MemexProjectColumnValueUpdate
  #   - github.memex.v0.MemexProjectColumnValueDestroy
  #   - github.memex.v1.MemexProjectColumnUpdate
  #   - github.memex.v1.MemexProjectColumnDestroy
  #
  # Rollout uses the generic split-processor mechanism:
  #   - :memex_denormalization_split_processor_enabled (actor-targeted by stream_processor_key)
  #     gates whether THIS processor is active.
  #   - :memex_denormalization_split_processor_skip_topics (actor-targeted by stream_processor_key)
  #     tells the DEFAULT processor to stop handling these topics.
  #
  # See `DenormalizationProcessor` for full documentation on the processing model.
  class DenormalizationProcessorColumnChanges < DenormalizationProcessor
    DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-projects-denormalization-processor-column-changes", String)
    METRIC_PREFIX = T.let("memex.#{DEFAULT_GROUP_ID}", String)

    sig { override.returns(MemexProjectColumn::Interface::Indexable::Processor::Base::StreamProcessorKey) }
    def self.stream_processor_key
      MemexProjectColumn::Interface::Indexable::Processor::Base::StreamProcessorKey::ColumnChanges
    end

    exempt_from_tenant_context_requirement

    sig { override.params(kwargs: T.untyped).void }
    def setup(**kwargs)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= MemexProjectColumn::Interface::Indexable::Processor.registered_topics_for_key(self.class.stream_processor_key)
      self.metric_prefix = METRIC_PREFIX
      @transient_error_max_retries = T.let(TRANSIENT_ERROR_RETRIES, T.nilable(Integer))
    end

    sig { override.params(message: GitHub::StreamProcessors::Message).returns(Result) }
    def process_message(message)
      unless MemexProjectColumn::Interface::Indexable::Processor.topic_matches_key?(message.topic, self.class.stream_processor_key)
        return skip("process_message", message, "topic-not-owned-by-processor")
      end

      unless FeatureFlag.vexi.enabled?(:memex_denormalization_split_processor_enabled, self.class.stream_processor_key_actor, default: false)
        return skip("process_message", message, "feature-flag-disabled")
      end

      super
    end
  end
end
