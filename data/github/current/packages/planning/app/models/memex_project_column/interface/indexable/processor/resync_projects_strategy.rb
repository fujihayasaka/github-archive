# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  # ResyncProjectsStrategy serves as an indexable strategy for re-building the Elasticsearch documents for individual
  # projects from scratch, particularly when patching Elasticsearch documents proves inadequate.
  #
  # Patching documents in Elasticsearch, done using scripting, offers a powerful option for batch-updating documents
  # using a scripting language. Despite its general efficiency, certain scenarios make Elasticsearch scripting
  # unsuitable for updating specific project items or column values when a GitHub resource is modified.
  #
  # In indexable processors, typically listening to Hydro messages signals modifications (creation, updates, or
  # deletion) to a GitHub resource, necessitating updates to project items. However, Hydro messages might not always
  # provide enough contextual information for generating the static values required to patch an exist project item
  # document.
  #
  # Given the intensive process of reindexing, it's advised to employ this strategy only when document patching is
  # deemed not the ideal approach.
  module ResyncProjectsStrategy
    extend T::Helpers
    include GitHub::Memoizer

    MAX_RESYNC_RETRIES = 2
    METRIC_PREFIX = T.let("memex.github-#{Rails.env}-resync-projects-strategy", String)

    abstract!
    requires_ancestor { MemexProjectColumn::Interface::Indexable::Processor::Base }

    sig { returns(T.nilable(T::Array[Integer])) }
    attr_reader :failed_project_ids

    sig { params(args: T.untyped, kwargs: T.untyped).void }
    def initialize(*args, **kwargs)
      @failed_project_ids = T.let(nil, T.nilable(T::Array[Integer]))
      super
    end

    sig do
      params(es_client: Search::Memex::Client).returns(ResyncProjectsResult)
    end
    def update(es_client)
      project_ids = project_ids_to_resync
      @failed_project_ids = enqueue_resyncs_with_retries(project_ids:)
      updated_memex_ids = project_ids - @failed_project_ids
      failure_reason = if @failed_project_ids.present?
        FailureReason::PARTIAL_RESYNC
      end

      ResyncProjectsResult.new(updated_memex_ids:, failure_reason:)
    end

    sig do
      params(project_ids: T::Array[Integer], tries_remaining: Integer).returns(T::Array[Integer])
    end
    private def enqueue_resyncs_with_retries(project_ids:, tries_remaining: MAX_RESYNC_RETRIES)
      GitHub.dogstats.increment("#{METRIC_PREFIX}.resync", tags: ["topic:#{message.topic}"])

      failed_project_ids = MemexProject::ResyncItems.resync_later(project_ids)

      return [] unless failed_project_ids.present?
      return failed_project_ids unless tries_remaining > 0

      enqueue_resyncs_with_retries(
        project_ids: failed_project_ids,
        tries_remaining: tries_remaining - 1,
      )
    end

    # When a ResyncProjectsStrategy processor fails to be processed, we will attempt to resync the projects that were
    # known to have failed to resync, otherwise fallback to the last-resort measure of resyncing the entire project(s)
    # that a given message would have affected.
    sig { returns(T::Array[Integer]) }
    def project_ids_to_resync_on_failure
      if (project_ids = failed_project_ids)
        project_ids
      else
        project_ids_to_resync
      end
    end

    # This method should return an array of ids for projects that are expected to be resynced.
    sig { abstract.returns(T::Array[Integer]) }
    def project_ids_to_resync; end
  end
end
