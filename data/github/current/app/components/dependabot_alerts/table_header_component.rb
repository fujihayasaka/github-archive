# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TableHeaderComponent < ApplicationComponent
    attr_reader :repository, :alerts_page_path, :menu_content_path, :query, :query_string, :dismissal_reasons, :show_bulk_edit

    def initialize(repository:, alerts_page_path:, menu_content_path:, query:, query_string:, current_user: nil, dismissal_reasons: {}, show_bulk_edit: false)
      @current_user = current_user
      @repository = repository
      @alerts_page_path = alerts_page_path
      @menu_content_path = menu_content_path
      @query = query
      @query_string = query_string
      @dismissal_reasons = dismissal_reasons
      @show_bulk_edit = show_bulk_edit
    end

    delegate :open_count, :closed_count, to: :query

    # This method is used to generate the query string for both "is" and "sort" filters.
    #
    # For sort filter:
    #     If the option is currently selected, we want to return to the default state when
    #     the user deselects it. This is done by remove_qualifier, which removes the qualifier:value
    #     pair from the current query string.
    #
    #     If the option is not selected, we want to apply this new option when the user selects it,
    #     which means we have to remove the current value in the query and replace it with this one.
    #     This additional step is done by add_or_replace.
    #
    # Meanwhile, we can't deselect open and closed state, so we'll always be doing remove and replace
    # for "is" filter.
    def query_string_for(str)
      qualifier, value = str.split(":")
      new_query_string = Search::Queries::SecurityCenter::DependabotAlertsQuery.remove_qualifier(query_string, qualifier.to_sym)
      new_query_string = Search::Queries::SecurityCenter::DependabotAlertsQuery.add_or_replace(new_query_string, qualifier.to_sym, value) unless sort_selected?(value)

      new_query_string
    end

    def open_selected?
      query.open?
    end

    def closed_selected?
      query.closed?
    end

    def each_sort_option
      sort_options.each do |label, slug|
        yield label, slug, sort_selected?(slug)
      end
    end

    memoize def sort_options
      options = [
        ["Newest", "newest"],
        ["Oldest", "oldest"],
        ["Severity", "severity"],
        ["Manifest path", "manifest-path"],
        ["Package name", "package-name"]
      ]

      options.prepend ["Most important", "most-important"] if can_sort_by_most_important?

      if allow_epss_percentage?
        options << ["EPSS Percentage ASC", "epss-percentage-asc"]
        options << ["EPSS Percentage DESC", "epss-percentage-desc"]
      end

      options
    end

    def sort_selected?(slug)
      sort_mapping = Search::Queries::SecurityCenter::DependabotAlertsQuery.sort_mapping(can_sort_by_most_important: can_sort_by_most_important?)
      query.sorted_by?(sort_mapping[slug])
    end

    def can_sort_by_most_important?
      if query.scope == :organization
        !query.organization.feature_enabled?(:dependabot_alerts_restrict_most_important_sort)
      else
        query.scope != :business
      end
    end

    def show_manifest_filter?
      query.scope == :repository
    end

    def show_organization_filter?
      query.scope == :business
    end

    def show_repository_filter?
      query.scope != :repository
    end

    def show_sort_filter?
      query.scope != :organization || !query.organization&.feature_enabled?(:dependabot_alerts_hide_org_sort)
    end

    def dependabot_alerts_path(q:)
      alerts_page_path.call(q: query_string_for(q))
    end

    def organization_filter_path(q:)
      menu_content_path.call(menu_content: "org", q: q)
    end

    def repository_filter_path(q:)
      menu_content_path.call(menu_content: "repo", q: q)
    end

    def manifest_filter_path(q:)
      menu_content_path.call(menu_content: "manifest", q: q)
    end

    def package_filter_path(q:)
      menu_content_path.call(menu_content: "package", q: q)
    end

    def ecosytem_filter_path(q:)
      menu_content_path.call(menu_content: "ecosystem", q: q)
    end

    def severity_filter_path(q:)
      menu_content_path.call(menu_content: "severity", q: q)
    end

    def closed_as_filter_path(q:)
      menu_content_path.call(menu_content: "resolution", q: q)
    end

    def render_select_panel(id:, button_content:, src:, title:, test_selector: "")
      render Primer::Alpha::SelectPanel.new(
        fetch_strategy: :eventually_local,
        id: id,
        src: src,
        title: title,
        select_variant: :multiple,
        preload: true,
        test_selector: test_selector,
      ) do |panel|
        panel.with_show_button(scheme: :invisible, color: :muted, font_weight: :normal) do |button|
          button.with_trailing_action_icon(icon: :'triangle-down')
          button_content
        end
      end
    end

    def filter_dropdown(id:, button_content:, src:, menu_aria_label:, test_selector: "", align_right: true)
      render Primer::Experimental::SelectMenuComponent.new(
        id: id,
        align_right:,
        position: :relative,
        test_selector: test_selector,
        details: {
          overlay: :default,
        },
        menu: {
          preload: true,
          src: src,
          tag: "details-menu",
          params: {
            aria: {
              label: menu_aria_label
            },
          }
        },
        modal: { params: { font_size: 5 } },
      ) do |c|
        c.with_summary(
          legacy_button_component: false,
          scheme: :invisible,
          variant: :medium,
          font_weight: :normal,
          color: :muted
        ).with_content(button_content)
      end
    end

    def dismiss_all_path
      repository_alerts_dismiss_many_path(
        user_id: repository.owner,
        repository: repository,
      )
    end

    def allow_epss_percentage?
      current_user&.feature_enabled?(:advisory_db_epss_dependabot_ui)
    end
  end
end
