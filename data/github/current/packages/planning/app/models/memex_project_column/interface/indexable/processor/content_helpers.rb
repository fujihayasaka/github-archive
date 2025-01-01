# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # This module provides optional helpers for Indexable::Processor::Base implementations that rely on content like
    # Issue and PullRequest records.
    module ContentHelpers
      extend ActiveSupport::Concern
      extend T::Helpers
      include GitHub::Memoizer
      abstract!

      requires_ancestor { MemexProjectColumn::Interface::Indexable::Processor::Base }

      # Any processor that includes this module must implement a `content` method that returns the content record for use
      # elsewhere. The expectation is that this method will be useful for both the processor's internal logic and for
      # the other methods defined in this module. Since reuse is likely, the method should be almost certainly be memoized.
      sig { abstract.returns(T.nilable(T.any(Issue, PullRequest))) }
      memoize def content; end

      # Many field implementations derive their elasticsearch document by traversing item.content. If a processor
      # has already fetched a content record, we don't want to have to fetch it again, so we explicitly prefill here.
      sig { returns(T::Array[MemexProjectItem]) }
      memoize def project_items_for_content
        raise CanonicalDataMissingError unless content.present?

        GitHub::PrefillAssociations.prefill_associations(T.must(content).memex_project_items, :content, available_records: [content])
        T.must(content).memex_project_items.to_a
      end

      sig do
        params(
          es_client: Search::Memex::Client,
          field_class: T.class_of(MemexProjectColumn::Field::Base),
        )
        .returns(Elastomer::Interfaces::Api::Bulk::Response::Body)
      end
      def bulk_update_field_values_for_content(es_client, field_class:)
        items = project_items_for_content
        # In some cases, all project items have been deleted by the time we get to this stage of the pipeline, in which case
        # we should just abort.
        raise CanonicalDataMissingError unless items.present?

        # Find all columns in a single query (instead of n+1) and key them by the project item id they're related to. This will
        # make it easier to find them later.
        columns_by_item_id = MemexProjectColumn
          .where(
            memex_project_id: items.map { _1.memex_project_id },
            data_type: field_class.data_type,
          )
          .index_by do |column|
            items.find { _1.memex_project_id == column.memex_project_id }&.id
          end

        es_client.bulk do |bulk|
          items.each do |project_item|
            if field = columns_by_item_id[project_item.id]&.to_field
              bulk.update(
                { script: field.elasticsearch_field_value_update_script(project_item).to_hash },
                { _id: project_item.id, _routing: project_item.memex_project_id, type: document_type, retry_on_conflict: 3 }
              )
            end
          end
        end
      end
    end
  end
end
