# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    class SearchComponent < GitHub::FilterInputComponent
      extend T::Sig

      def initialize(
        user: nil,
        scope: nil,
        icon: :search,
        method: :get,
        path: "?",
        pjax: false,
        placeholder: "Search",
        query: "",
        show_org_level_suggestions: false,
        show_business_level_suggestions: false,
        show_user_repo_suggestions: false,
        filter_suggestions_path: nil,
        custom_patterns_available: true,
        show_confidence_suggestions: false
      )
        @user = user
        @scope = scope
        @custom_patterns_available = custom_patterns_available
        @show_org_level_suggestions = show_org_level_suggestions
        @show_business_level_suggestions = show_business_level_suggestions
        @show_user_repo_suggestions = show_user_repo_suggestions
        @filter_suggestions_path = filter_suggestions_path
        @show_confidence_suggestions = show_confidence_suggestions

        super(
          tag_name: "secret-scanning-filter",
          icon: icon,
          method: method,
          path: path,
          use_pjax: pjax,
          placeholder: placeholder,
          default_value: Search::Queries::SecurityCenter::SecretScanningQuery::default_query(show_confidence_suggestions),
          query: query,
          suggestable_items: suggestable_items,
          input_test_selector: "secret-scanning-search-box",
          my: 0,
        )
      end

      def business_level_suggestions
        {
          owner: {
            description: "user or organization name",
            path: @filter_suggestions_path&.call(suggestion: SecretScanningControllerHelper::GroupByAggregation::OWNER) || "",
            negatable: true,
          },
          "owner-type": {
            description: suggestable_owner_types.map { |option| option[:value] }.join(", "),
            suggestions: suggestable_owner_types,
            negatable: true
          },
        }
      end

      def org_level_suggestions
        {
          repo: {
            description: "repo-name",
            path: @filter_suggestions_path&.call(suggestion: "repo") || "",
            negatable: true,
          }
        }
      end

      def suggestable_sorts
        ::Search::Queries::SecurityCenter::SecretScanningQuery::sort_options.map { |option| { value: option[:slug] } }
      end

      def suggestable_resolutions
        opts = ::Search::Queries::SecurityCenter::SecretScanningQuery::RESOLUTION_OPTIONS
        unless @custom_patterns_available
          opts = opts.reject { |item| item[:feature] == :custom_pattern }
        end

        opts.map { |option| { value: option[:slug] } }
      end

      def suggestable_validities
        opts = ::Search::Queries::SecurityCenter::SecretScanningQuery::VALIDITY_OPTIONS
        opts.map { |option| { value: option[:slug] } }
      end

      def suggestable_bypass_states
        opts = ::Search::Queries::SecurityCenter::SecretScanningQuery::BYPASSED_OPTIONS
        opts.map { |option| { value: option[:slug] } }
      end

      def suggestable_owner_types
        opts = ::Search::Queries::SecurityCenter::SecretScanningQuery::OWNER_TYPE_OPTIONS
        opts.map { |option| { value: option[:slug] } }
      end

      sig { returns(T::Array[{ value: String }]) }
      def suggestable_confidences
        opts = ::Search::Queries::SecurityCenter::SecretScanningQuery::CONFIDENCES
        opts.map { |option| { value: option } }
      end

      def suggestable_items
        secret_type_desc = "provider-pattern, custom-pattern"
        unless @custom_patterns_available
          secret_type_desc = "provider-pattern"
        end

        items = {
          is: {
            description: "open, closed",
            suggestions: [
              { value: "open" },
              { value: "closed" },
            ]
          },
          "secret-type": {
            description: secret_type_desc,
            path: @filter_suggestions_path&.call(suggestion: "secret-type") || "",
            negatable: true,
          },
          provider: {
            description: "provider-name",
            path: @filter_suggestions_path&.call(suggestion: "provider") || "",
            negatable: true,
          },
          resolution: {
            description: suggestable_resolutions.map { |option| option[:value] }.join(", "),
            suggestions: suggestable_resolutions,
            negatable: true,
          },
          sort: {
            description: suggestable_sorts.map { |sort| sort[:value] }.join(", "),
            suggestions: suggestable_sorts
          },
          team: {
            description: "team",
            path: @filter_suggestions_path&.call(suggestion: "team") || "",
            negatable: true,
          },
          topic: {
            description: "repo-topic",
            path: @filter_suggestions_path&.call(suggestion: "topic") || "",
            negatable: true,
          },
        }
        items.merge!(org_level_suggestions) if @show_org_level_suggestions
        items.merge!(business_level_suggestions) if @show_business_level_suggestions
        if @show_confidence_suggestions
          items[:confidence] = {
            description: suggestable_confidences.map { |option| option[:value] }.join(", "),
            suggestions: suggestable_confidences,
          }
        end
        items[:validity] = {
          description: suggestable_validities.map { |option| option[:value] }.join(", "),
          suggestions: suggestable_validities,
          negatable: false,
        }
        items[:bypassed] = {
          description: suggestable_bypass_states.map { |option| option[:value] }.join(", "),
          suggestions: suggestable_bypass_states,
          negatable: false,
        }

        # Custom properties should always be last in the list.
        if @show_org_level_suggestions && @scope.present? && @scope.is_a?(::Organization) && @user.present?
          ::SecurityCenter::Helpers::CustomProperties.new(org: @scope, user: @user).definitions_for_frontend.each do |prop_definition|
            item_name = "props.#{prop_definition.fetch(:name)}"

            items[item_name.to_sym] = {
              description: "Custom property: #{prop_definition.fetch(:name)}",
              path: @filter_suggestions_path&.call(suggestion: item_name) || "",
              negatable: true
            }
          end
        end

        items
      end
    end
  end
end
