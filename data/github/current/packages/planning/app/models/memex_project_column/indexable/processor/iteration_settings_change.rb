# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    class IterationSettingsChange < Base
      extend T::Sig
      include GitHub::Memoizer

      # Option is used here to refer to each Iteration item of an Iteration field to disambiguate
      # and standardize the nomenclature with single_select. Inside an Iteration field
      # configuration, the arrays listing the individual iterations are keyed as "iterations"
      # and "completed_iterations", making it hard to know if the word iteration refers
      # to the field itself or to its items.
      Option = T.type_alias { T::Hash[T.untyped, T.untyped] }
      SettingsOptions = T.type_alias { T::Array[Option] }

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v1\.MemexProjectColumnUpdate\Z/
        ]
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        MemexProjectColumn.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        return false unless project_id.present? && field_id.present?

        return false unless iteration_data_type?

        return false unless iteration_settings_updated?

        return false unless existing_iteration_options_updated?

        true
      end

      sig { override.returns(T::Boolean) }
      def matching_elasticsearch_documents?
        @index.count(es_query, routing: T.must(project_id)) > 0
      end

      sig { override.returns(T::Boolean) }
      def canonical_data_present?
        model.present?
      end

      sig { override.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure
        [T.must(project_id)]
      end

      sig do override
        .params(es_client: ElasticsearchClient)
        .returns(T::Array[Elastomer::Interfaces::Api::UpdateByQuery::Response])
      end
      def update(es_client)
        canonical_iterations = T.must(model).settings_all_iterations
        params = Elastomer::Interfaces::Api::UpdateByQuery::Request::Params.new(routing: project_id)

        diff_changes.map do |iteration_option|
          query = {
            bool: {
              filter: query_for_option(iteration_option)
            }
          }
          script = update_script_for_option(iteration_option, canonical_iterations)
          body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query:, script:)
          es_client.update_by_query(body, params)
        end
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        @message.value.dig(:memex_project, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def field_id
        @message.dig(:memex_project_column, :id)
      end

      sig { returns(T::Boolean) }
      private def iteration_data_type?
        @message.dig(:memex_project_column, :data_type) == MemexProjectColumn::Iteration.data_type.to_s
      end

      sig { returns(T::Boolean) }
      private def iteration_settings_updated?
        previous_changes.dig("settings").present?
      end

      sig { returns(T::Boolean) }
      private def existing_iteration_options_updated?
        diff_changes.present?
      end

      # The previous_changes field contains a JSON string that contains all the information
      # about the updated iteration options.
      sig { returns(T::Hash[String, T.untyped]) }
      memoize private def previous_changes
        JSON.parse(@message.dig(:previous_changes))
      end

      sig { returns(SettingsOptions) }
      private def diff_changes
        old_options, new_options = previous_changes["settings"].map do |settings|
          configuration = settings.dig("configuration")
          next [] unless configuration
          (configuration.dig("iterations") || []) | (configuration.dig("completed_iterations") || [])
        end

        # Newly added iterations are skipped, since they won't have any item associated with it
        # the moment they're created. Field values using the newly added iterations are expected
        # to be processed by the `IterationValueCreate` processor.
        old_options - new_options
      end

      sig { returns(T.nilable(MemexProjectColumn::Field)) }
      memoize private def model
        MemexProjectColumn.find_by(id: field_id)&.to_field
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        # Construct a single query that will search the index for any documents that contain any of the 1 or more
        # iteration options that have changed.
        nested_queries = diff_changes.map { |option| query_for_option(option) }
        {
          query: {
            bool: {
              filter: {
                bool: {
                  # In filter contexts, with no other query clauses, should acts like an OR + minimum_should_match: 1
                  should: nested_queries
                }
              }
            }
          }
        }
      end

      # Locate any documents that have a value for this particular iteration field that matches the
      # provided iteration option.
      sig { params(option: Option).returns(T::Hash[Symbol, T.untyped]) }
      def query_for_option(option)
        value = option.dig("id")
        {
          nested: {
            path: "field_values",
            query: {
              bool: {
                filter: [
                  { term: { "field_values.field_id": field_id } },
                  { term: { "field_values.#{MemexProjectColumn::Iteration.value_name}.id": value } }
                ]
              }
            }
          }
        }
      end

      # Construct the update script for the given iteration option.
      sig do
        params(
          iteration_option: Option,
          canonical_iteration_options: T::Array[T::Hash[T.untyped, T.untyped]]
        )
        .returns(Elastomer::Interfaces::Api::Request::Script)
      end
      def update_script_for_option(iteration_option, canonical_iteration_options)
        canonical_iteration_option = canonical_iteration_options.find { |opt| opt["id"] == iteration_option["id"] }
        if canonical_iteration_option.present?
          # If the canonical iteration is present, it means the event was an update and we should just update the
          # value accordingly (or no-op if the updated value is already present)
          Elastomer::Interfaces::Api::Request::Script.new(
            source: """
              def field = ctx._source.field_values.find(f -> f.field_id == params.field_id);
              if (field == null || field[params.value_name] == params.value) {
                ctx.op = 'noop';
              } else {
                field[params.value_name] = params.value;
              }
            """,
            params: {
              field_id:,
              value_name: MemexProjectColumn::Iteration.value_name,
              value: updated_document(canonical_iteration_option).to_hash
            }
          )
        else
          # If the canonical iteration is not present, it means the iteration was deleted and we should remove the
          # field entirely.
          Elastomer::Interfaces::Api::Request::Script.new(
            source: """
              boolean removed = ctx._source.field_values.removeIf(f -> f.field_id == params.field_id);
              if (!removed) {
                ctx.op = 'noop';
              }
            """,
            params: { field_id:, }
          )
        end
      end

      sig { params(option: Option).returns(Elastomer::Interfaces::Document::Iteration) }
      private def updated_document(option)
        Elastomer::Interfaces::Document::Iteration.new({
          id: option["id"],
          title: option["title"],
          duration: option["duration"],
          start_date: option["start_date"]
        })
      end
    end
  end
end
