# typed: strict
# frozen_string_literal: true

# This module provides helper methods for working with "special" field types: those that link existing data
# from elsewhere on GitHub, typically via the `content` association on a `MemexProjectItem`.
module MemexProjectColumn::SpecialFieldHelpers
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers
  requires_ancestor { MemexProjectColumn::Field }

  # This helper can be used in `Indexable#preload_elasticsearch_document` implementations to make sure that the
  # content association (and other associations rooted at content) has been preloaded prior to other preloads that
  # depend on it.
  #
  # EXAMPLE:
  #
  #   def preload_elasticsearch_document_data(items)
  #     preload_content_tree(items)                    # Make sure the content association has been preloaded
  #     issues = items.select(&:issue?).map(&:content) # Now we can map over content without making extra queries
  #     GitHub::PrefillAssociations.prefill_associations(issues, :assignees)
  #   end
  #
  sig { params(items: T::Array[MemexProjectItem]).void }
  private def preload_content_tree(items)
    GitHub::PrefillAssociations.prefill_associations(items, [:content, :repository])
    GitHub.flipper.preload([:html_pipeline_bad_emoji])

    pull_requests = items.select(&:pull_request?).map(&:content).compact
    GitHub::PrefillAssociations.prefill_associations(pull_requests, :issue)

    pull_request_issues = pull_requests.map(&:issue).compact
    ordinary_issues = items.select(&:issue?).map(&:content).compact

    GitHub::PrefillAssociations.prefill_associations(
      pull_requests + pull_request_issues + ordinary_issues,
      :repository,
      available_records: items.map(&:repository).compact
    )
  end
end
