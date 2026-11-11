# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    class SingleSelectSettingsChange < Base
      include GitHub::Memoizer

      Option = T.type_alias { T::Hash[T.untyped, T.untyped] }
      SettingsOptions = T.type_alias { T::Array[Option] }
      ParsedSettingsOptions = T.type_alias { { before: SettingsOptions, after: SettingsOptions } }

      # Feature flag enabling the ES-relevant diff filter. When enabled, settings changes
      # that only touch option fields not stored in Elasticsearch (color, description,
      # name_html, description_html) short-circuit before triggering any update_by_query.
      # See `diff_changes` for details.
      ES_RELEVANT_DIFF_FILTER_FLAG = T.let(
        :es_relevant_diff_filter_flag,
        Symbol
      )

      # Tracks how many update_by_query calls would be (or were) skipped per message
      # by the ES-relevant diff filter. Always emitted in shadow mode (regardless of FF
      # state) so the impact can be measured before and after rollout. Tagged with
      # `enabled:true|false` to distinguish shadow vs. live behavior.
      METRIC_NAME_DIFF_FILTER_SKIPPED = T.let(
        "memex.indexable.processor.single_select_settings_change.diff_filter_skipped",
        String
      )

      # Fields written to ES by `updated_value`. Changes to other option fields
      # (color, description, name_html, description_html) do not require any ES
      # update.
      ES_RELEVANT_OPTION_KEYS = T.let(%w[id name].freeze, T::Array[String])

      sig { override.returns(T::Array[Regexp]) }
      def self.topics
        [
          /github\.memex\.v1\.MemexProjectColumnUpdate\Z/
        ]
      end

      sig { override.returns(StreamProcessorKey) }
      def self.stream_processor_key
        StreamProcessorKey::ColumnChanges
      end

      sig { override.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster
        MemexProjectColumn.cluster_name
      end

      sig { override.returns(T::Boolean) }
      def valid_message?
        return false unless project_id.present? && field_id.present?

        # Skip processing for other kinds of columns that trigger this event (e.g. iteration columns)
        return false unless data_type_matches?

        # If the settings object isn't present or isn't an array, no options have changed and we can skip.
        return false unless previous_changes.dig("settings")&.is_a?(Array)

        # The diff will be empty if the only changes made to settings were to add new options.
        # In that case, no existing indexed docs need updating.
        return false if diff_changes.empty?

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

      sig { override.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models
        [model]
      end

      # Tags the `memex.indexable.processor.index_time{action:update}` distribution
      # with the bucketed count of options that triggered update_by_query calls and
      # the current state of the ES-relevant diff filter feature flag.
      sig { override.returns(T::Hash[String, String]) }
      def update_extra_tags
        {
          "diff_changes_size" => diff_changes_size_bucket(diff_changes.size),
          "es_relevant_diff_filter_enabled" => es_relevant_diff_filter_enabled?.to_s,
        }
      end

      sig { returns(T::Boolean) }
      private def data_type_matches?
        @message.dig(:memex_project_column, :data_type) == MemexProjectColumn::Field::SingleSelect.data_type.to_s
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        @message.value.dig(:memex_project, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def field_id
        @message.dig(:memex_project_column, :id)
      end

      sig { returns(T::Hash[String, T.untyped]) }
      memoize private def previous_changes
        JSON.parse(@message.dig(:previous_changes))
      end

      # Returns the set of options that require an update_by_query.
      #
      # The raw diff (`old_options - new_options`) treats ANY field difference as
      # significant, which causes spurious UBQs when only color/description/HTML
      # fields change — those fields are not stored in ES (see `updated_value`),
      # so the resulting UBQ resolves to a server-side Painless noop after paying
      # the full network + refresh cost.
      #
      # When `projects_single_select_settings_change_es_relevant_diff_filter` is
      # enabled, the diff is restricted to options whose ES-indexed fields
      # (`id`, `name`) actually changed. The filter is computed and instrumented
      # in all cases so the avoidable-UBQ volume is visible.
      sig { returns(SettingsOptions) }
      memoize private def diff_changes
        parsed = parsed_settings_options
        raw = parsed[:before] - parsed[:after]

        filtered = if raw.empty?
          raw
        else
          new_options_es_keys = parsed[:after].to_set { |opt| es_relevant_keys(opt) }
          raw.reject { |old_opt| new_options_es_keys.include?(es_relevant_keys(old_opt)) }
        end

        instrument_diff_filter(raw_size: raw.size, filtered_size: filtered.size)

        es_relevant_diff_filter_enabled? ? filtered : raw
      end

      sig { returns(ParsedSettingsOptions) }
      memoize private def parsed_settings_options
        before, after = previous_changes["settings"]
        { before: parse_options(before), after: parse_options(after) }
      end

      sig { params(settings: T.nilable(T::Hash[String, T.untyped])).returns(SettingsOptions) }
      private def parse_options(settings)
        return [] if settings.nil?
        settings["options"] || []
      end

      sig { params(option: T.nilable(T::Hash[String, T.untyped])).returns(T::Hash[String, T.untyped]) }
      private def es_relevant_keys(option)
        return {} if option.nil?
        ES_RELEVANT_OPTION_KEYS.each_with_object({}) { |key, hash| hash[key] = option[key] }
      end

      sig { returns(T::Boolean) }
      private def es_relevant_diff_filter_enabled?
        FeatureFlag.vexi.enabled?(
          ES_RELEVANT_DIFF_FILTER_FLAG,
          processor_class_actor,
          default: false,
        )
      end

      # Emits a distribution of the number of update_by_query calls the ES-relevant
      # diff filter would skip (when disabled) or did skip (when enabled). No-op when
      # the filter would not have changed anything for this message.
      sig { params(raw_size: Integer, filtered_size: Integer).void }
      private def instrument_diff_filter(raw_size:, filtered_size:)
        skipped = raw_size - filtered_size
        return if skipped <= 0

        GitHub.dogstats.distribution(
          METRIC_NAME_DIFF_FILTER_SKIPPED,
          skipped,
          tags: [
            "enabled:#{es_relevant_diff_filter_enabled?}",
            "raw_size_bucket:#{diff_changes_size_bucket(raw_size)}",
          ]
        )
      end

      sig { params(size: Integer).returns(String) }
      private def diff_changes_size_bucket(size)
        case size
        when 0 then "0"
        when 1 then "1"
        when 2..5 then "2-5"
        when 6..10 then "6-10"
        when 11..25 then "11-25"
        when 26..50 then "26-50"
        else "51+"
        end
      end

      sig { returns(T.nilable(MemexProjectColumn::Field::Base)) }
      memoize private def model
        MemexProjectColumn.find_by(id: field_id)&.to_field
      end

      sig { returns(T::Hash[T::untyped, T::untyped]) }
      memoize private def es_query
        # Construct a single query that will search the index for any documents that contain any of the 1 or more
        # options that have changed.
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

      # Locate any documents that have a value for this particular single-select that matches the passed in option
      sig { params(option: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
      def query_for_option(option)
        value = option&.dig("id")
        {
          nested: {
            path: "field_values",
            query: {
              bool: {
                filter: [
                  { term: { "field_values.field_id": field_id } },
                  { term: { "field_values.#{MemexProjectColumn::Field::SingleSelect.value_name}.id": value } }
                ]
              }
            }
          }
        }
      end

      # Construct the update script for the given option.
      sig do
        params(
          option: Option,
          latest_options: T::Hash[T.untyped, T.untyped]
        )
        .returns(Elastomer::Interfaces::Api::Request::Script)
      end
      def update_script_for_option(option, latest_options)
        latest_option = latest_options[option["id"]]
        if latest_option.present?
          # If the canonical single select option is present, it means the event was an update and we should just update the
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
              value_name: MemexProjectColumn::Field::SingleSelect.value_name,
              value: updated_value(latest_option).to_hash
            }
          )
        else
          # If the canonical single select option is not present, it means the option was deleted and we should remove the
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

      sig do override
        .params(es_client: Search::Memex::Client)
        .returns(T::Array[Elastomer::Interfaces::Api::UpdateByQuery::Response])
      end
      def update(es_client)
        params = Elastomer::Interfaces::Api::UpdateByQuery::Request::Params.new(routing: project_id, refresh: update_by_query_refresh_strategy)
        latest_options = T.must(model).settings.dig("options").index_by { |opt| opt["id"] }
        # Post 1 update per option that has changed. This may not be the long-term solution, but should be a decent
        # compromise on performance and complexity for now.
        diff_changes.map do |option|
          query = {
            bool: {
              filter: query_for_option(option)
            }
          }
          script = update_script_for_option(option, latest_options)
          body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query:, script:)
          es_client.update_by_query(body, params)
        end
      end

      sig { params(option: Option).returns(Elastomer::Interfaces::Document::SingleSelect) }
      private def updated_value(option)
        Elastomer::Interfaces::Document::SingleSelect.new({
          id: option["id"],
          name: option["name"],
        })
      end
    end
  end
end
