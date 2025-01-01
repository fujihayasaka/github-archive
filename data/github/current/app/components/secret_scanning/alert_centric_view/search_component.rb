# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    class SearchComponent < GitHub::FilterInputComponent
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
        show_campaign_filter: false,
        show_assignee_filter: false,
        show_business_level_suggestions: false,
        show_user_repo_suggestions: false,
        filter_suggestions_path: nil,
        custom_patterns_available: true,
        show_results_category_suggestions: false,
        plaid_ui_filters_enabled: false,
        search_context: nil
      )
        @user = user
        @scope = scope
        @custom_patterns_available = custom_patterns_available
        @show_org_level_suggestions = show_org_level_suggestions
        @show_business_level_suggestions = show_business_level_suggestions
        @show_user_repo_suggestions = show_user_repo_suggestions
        @filter_suggestions_path = filter_suggestions_path
        @show_results_category_suggestions = show_results_category_suggestions
        @plaid_ui_filters_enabled = plaid_ui_filters_enabled
        @show_campaign_filter = show_campaign_filter
        @show_assignee_filter = show_assignee_filter

        super(
          tag_name: "secret-scanning-filter",
          icon: icon,
          method: method,
          path: path,
          use_pjax: pjax,
          placeholder: placeholder,
          default_value: Search::Queries::SecurityCenter::SecretScanningQuery::default_query(show_results_category_suggestions),
          query: query,
          suggestable_items: suggestable_items,
          input_test_selector: "secret-scanning-search-box",
          flex: 1,
          border_radius: 0,
          search_context: search_context,
          my: 0,
        )
      end

      def business_level_suggestions
        suggestions = {
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

        if @show_assignee_filter
          suggestions[:assignee] = {
            description: "username",
            path: @filter_suggestions_path&.call(suggestion: "assignee") || "",
            negatable: true
          }
        end

        suggestions
      end

      def org_level_suggestions
        suggestions = {
          repo: {
            description: "repo-name",
            path: @filter_suggestions_path&.call(suggestion: "repo") || "",
            negatable: true,
          }
        }

        if @show_campaign_filter
          suggestions[:campaign] = {
            description: "open, closed, none",
            suggestions: [{ value: "open" }, { value: "closed" }, { value: "none" }],
            negatable: true
          }
        end

        if @show_assignee_filter
          suggestions[:assignee] = {
            description: "username",
            path: @filter_suggestions_path&.call(suggestion: "assignee") || "",
            negatable: true
          }
        end

        suggestions
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
      def suggestable_results_categories
        opts = ::Search::Queries::SecurityCenter::SecretScanningQuery::RESULTS_CATEGORIES
        opts.map { |option| { value: option } }
      end

      def suggestable_items
        secret_type_desc = "provider-pattern, custom-pattern"
        unless @custom_patterns_available
          secret_type_desc = "provider-pattern"
        end

        is_description = if @plaid_ui_filters_enabled
          "open, closed, publicly-leaked, multi-repository"
        else
          "open, closed"
        end

        is_suggestions = if @plaid_ui_filters_enabled
          [{ value: "open" }, { value: "closed" }, { value: "publicly-leaked" }, { value: "multi-repository" }]
        else
          [{ value: "open" }, { value: "closed" }]
        end

        items = {
          is: {
            description: is_description,
            suggestions: is_suggestions,
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

        if @show_assignee_filter
          items[:has] = {
            description: "assignee",
            suggestions: [{ value: "assignee" }],
          }
          items[:no] = {
            description: "assignee",
            suggestions: [{ value: "assignee" }],
          }
        end

        items.merge!(org_level_suggestions) if @show_org_level_suggestions
        items.merge!(business_level_suggestions) if @show_business_level_suggestions
        if @show_results_category_suggestions
          items[Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY] = {
            description: suggestable_results_categories.map { |option| option[:value] }.join(", "),
            suggestions: suggestable_results_categories,
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
