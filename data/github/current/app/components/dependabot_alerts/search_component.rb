# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class SearchComponent < GitHub::FilterInputComponent
    attr_reader :current_user

    def initialize(
      icon: :search,
      method: :get,
      path: "?",
      pjax: false,
      placeholder: "Search all Dependabot alerts",
      default_value: "is:open ",
      query: "",
      query_parameter_key: "q",
      show_org_level_suggestions: false,
      show_business_level_suggestions: false,
      filter_suggestions_path: nil,
      current_user: nil,
      organization: nil
    )
      @show_business_level_suggestions = show_business_level_suggestions
      @show_org_level_suggestions = show_org_level_suggestions
      @filter_suggestions_path = filter_suggestions_path
      @current_user = current_user
      @organization = organization

      super(
        tag_name: "dependabot-alerts-filter",
        icon: icon,
        method: method,
        path: path,
        use_pjax: pjax,
        turbo_frame: "_self",
        placeholder: placeholder,
        default_value: default_value,
        query: query,
        query_parameter_key: query_parameter_key,
        suggestable_items: suggestable_items,
        form_test_selector: "alert-search-form",
        input_test_selector: "alert-search-field",
        reset_button_test_selector: "alert-search-reset",
        my: 0,
      )
    end

    private

    def suggestable_sorts
      @suggestable_sorts ||= sort_options.map { |option| { value: option } }
    end

    def sort_description
      sort_options.join(", ")
    end

    def sort_options
      return @sort_options if defined? @sort_options

      options = %w[newest oldest severity manifest-path package-name]
      options.prepend "most-important" if can_sort_by_most_important?

      @sort_options = options
    end

    def can_sort_by_most_important?
      !@show_business_level_suggestions
    end

    def suggestable_repo_types
      @suggestable_repo_types ||= [
        { value: "open" },
        { value: "closed" },
      ]
    end

    def suggestable_has_types
      @suggestable_has_types ||= [
        { value: "patch" },
      ]
    end

    def suggestable_scopes
      @suggestable_scopes ||= [
        { value: "runtime" },
        { value: "development" },
      ]
    end

    def business_level_suggestable_items
      {
        org: {
          description: "org-name",
          path: @filter_suggestions_path&.call(suggestion: "org") || "",
          negatable: true
        }
      }
    end

    def org_level_suggestable_items
      items = {
        repo: {
          description: "repo-name",
          path: @filter_suggestions_path&.call(suggestion: "repo") || "",
          negatable: true
        }
      }

      if @organization.present? && @current_user.present?
        ::SecurityCenter::Helpers::CustomProperties.new(org: @organization, user: @current_user).definitions_for_frontend.each do |prop_definition|
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

    def repo_level_suggestable_items
      {
        manifest: {
          description: "manifest-name",
          path: @filter_suggestions_path&.call(suggestion: "manifest") || "",
          negatable: true
        }
      }
    end

    def suggestable_items
      items = {
        resolution: {
          description: RepositoryVulnerabilityAlert::RESOLUTION_OPTIONS.map { |option| option[:slug] }.join(", "),
          suggestions: RepositoryVulnerabilityAlert::RESOLUTION_OPTIONS.map { |option| { value: option[:slug] } },
          negatable: true
        },
        severity: {
          description: "critical, high, moderate, low",
          suggestions: Vulnerability::SEVERITIES.map { |severity| { value: severity } }.reverse,
          negatable: true
        },
        package: {
          description: "package-name",
          path: @filter_suggestions_path&.call(suggestion: "package") || "",
          negatable: true
        },
        ecosystem: {
          description: "ecosystem-name",
          path: @filter_suggestions_path&.call(suggestion: "ecosystem") || "",
          negatable: true
        },
        sort: {
          description: sort_description,
          suggestions: suggestable_sorts
        },
        is: {
          description: "open, closed",
          suggestions: suggestable_repo_types
        },
        has: {
          description: "patch",
          suggestions: suggestable_has_types,
          negatable: true
        },
        scope: {
          description: "runtime, development",
          suggestions: suggestable_scopes,
          negatable: true
        },
        team: {
          description: "team-name",
          path: @filter_suggestions_path&.call(suggestion: "team") || "",
          negatable: true
        },
        topic: {
          description: "topic-name",
          path: @filter_suggestions_path&.call(suggestion: "topic") || "",
          negatable: true
        }
      }

      if @organization&.feature_enabled?(:dependabot_alerts_hide_org_sort)
        items.delete(:sort)
      end

      unless GitHub.enterprise?
        items[:resolution][:description] = items[:resolution][:description].clone + ", auto-dismissed"
        items[:resolution][:suggestions] = items[:resolution][:suggestions].clone << { value: "auto-dismissed" }
      end

      # If the user is on GHES, we don't want to show the
      # vulnerable-calls suggestion, as it's not supported.
      unless GitHub.enterprise?
        has = items[:has]
        has[:description] = has[:description] + ", vulnerable-calls"
        has[:suggestions] = has[:suggestions].clone << { value: "vulnerable-calls" }
      end

      if @show_business_level_suggestions
        items.merge!(business_level_suggestable_items).merge!(org_level_suggestable_items)
      elsif @show_org_level_suggestions
        items.merge!(org_level_suggestable_items)
      else
        items.merge!(repo_level_suggestable_items)
      end

      items
    end
  end
end
