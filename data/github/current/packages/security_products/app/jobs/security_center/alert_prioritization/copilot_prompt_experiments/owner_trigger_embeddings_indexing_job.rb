# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      # Indexes all repos in an owner for semantic search.
      class OwnerTriggerEmbeddingsIndexingJob < TimedJob
        include ::GitHub::SecurityCenter::LoggingHelper
        include BlackbirdIndexHelper

        queue_as :alert_prioritization_copilot_trigger_embeddings

        retry_on_dirty_exit
        retry_on_recoverable_exceptions

        locked_by timeout: ApplicationJob::DEFAULT_TIMEOUT, key: ->(job) do
          DEFAULT_LOCK_STRINGIFY_PROC.call([job.owner.id])
        end

        around_perform do |job, block|
          block.call if job.job_enabled?
        end

        sig { override.params(actor: ::User, owner: T.any(::Organization, ::User), max_sequence_num_processed_items: T.nilable(Integer), kwargs: T.untyped).void }
        def perform(actor:, owner:, max_sequence_num_processed_items: nil, **kwargs)
          super(actor:, owner:, max_sequence_num_processed_items:, **kwargs)
        end

        sig { override.params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).returns(T.all(T::Enumerable[T.untyped], Object)) }
        def fetch_batch(*args, offset_id:, **kwargs)
          return [] if !job_enabled?

          if max_sequence_num_processed_items.present? && sequence_num_processed_items >= T.must(max_sequence_num_processed_items)
            return []
          end

          owner
            .repositories
            .where(::Repository.arel_table[:id].gt(offset_id))
            .order(:id)
            .limit(1_000)
        end

        sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
        def process_item(*args, item:, **kwargs)
          return if !job_enabled?

          cir = CopilotIndexedRepositories.find_by(repository_id: item.id)

          if cir.nil? || cir.markdown_only
            ::CopilotIndexedRepositories.throttle_writes_with_retry do
              trigger_embeddings_indexing(actor, item, index_code: true, index_docs: true)
            end
          end
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def job_arguments
          arguments[0] || {}
        end

        sig { returns(::User) }
        def actor
          job_arguments.fetch(:actor)
        end

        sig { returns(T.any(::Organization, ::User)) }
        def owner
          job_arguments.fetch(:owner)
        end

        sig { returns(Integer) }
        def sequence_num_processed_items
          job_arguments.fetch(:sequence_num_processed_items, 0)
        end

        sig { returns(T.nilable(Integer)) }
        def max_sequence_num_processed_items
          job_arguments[:max_sequence_num_processed_items]
        end

        sig { returns(T::Boolean) }
        memoize def job_enabled?
          !::SecurityCenter::FeatureFlagHelper.disable_alert_prioritization_owner_trigger_embeddings_indexing_job?(owner)
        end
      end
    end
  end
end
