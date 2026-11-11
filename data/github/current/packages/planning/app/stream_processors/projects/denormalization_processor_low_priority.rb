# typed: strict
# frozen_string_literal: true

require "github/stream_processors/transient_error_resiliency_helpers"

module Projects
  # This processor handles topics from processors with a non-default `stream_processor_key`,
  # split out from the main DenormalizationProcessor to reduce blast radius and allow independent scaling.
  #
  # See `DenormalizationProcessor` for full documentation on the processing model.
  class DenormalizationProcessorLowPriority < DenormalizationProcessor
    DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-projects-denormalization-processor-low-priority", String)
    METRIC_PREFIX = T.let("memex.#{DEFAULT_GROUP_ID}", String)

    sig { override.returns(MemexProjectColumn::Interface::Indexable::Processor::Base::StreamProcessorKey) }
    def self.stream_processor_key
      MemexProjectColumn::Interface::Indexable::Processor::Base::StreamProcessorKey::LowPriority
    end

    exempt_from_tenant_context_requirement

    sig { override.params(kwargs: T.untyped).void }
    def setup(**kwargs)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= MemexProjectColumn::Interface::Indexable::Processor.registered_topics_for_key(self.class.stream_processor_key)
      self.metric_prefix = METRIC_PREFIX
      @transient_error_max_retries = T.let(TRANSIENT_ERROR_RETRIES, T.nilable(Integer))
    end
  end
end
