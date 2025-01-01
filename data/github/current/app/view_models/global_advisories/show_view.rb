# typed: true
# frozen_string_literal: true

require "advisory_db_toolkit"

module GlobalAdvisories
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :advisory, :dependabot_alerts_tab, :repository_alerts_scope, :open_alerts_count, :closed_alerts_count, :query, :form_advisory, :justification

    def after_initialize
      helpers.extend(VulnerabilityHelper, PackageDependenciesHelper, AnalyticsHelper)

      @form_advisory = @advisory
    end

    def repository_advisory
      advisory.repository_advisory
    end

    def has_readable_repository_advisory?
      return @has_readable_repository_advisory if defined? @has_readable_repository_advisory

      @has_readable_repository_advisory = advisory.repository_advisory.present? &&
        advisory.repository_advisory.readable_by?(current_user)
    end

    def repository
      repository_advisory&.repository
    end

    def has_repository?
      has_readable_repository_advisory? && repository.present?
    end

    def advisories_repository_issues_url
      "#{GitHub.url}/#{AdvisoryDB::ADVISORIES_REPOSITORY_NWO}/issues"
    end

    def ecosystem_compatibility_discussion_url
      "#{GitHub.url}/#{AdvisoryDB::ADVISORIES_REPOSITORY_NWO}/discussions/166"
    end

    def advisory_title
      AdvisoryDB::advisory_title(advisory)
    end

    def source_code_location_is_url?
      begin
        uri = URI.parse(advisory.source_code_location)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end

    def source_code_location_text
      return if advisory.source_code_location.blank?

      advisory.source_code_location.sub(/\Ahttps?:\/\/github.com\//, "")
    end

    def dotcom_suffix
      GitHub.single_or_multi_tenant_enterprise? ? " on GitHub.com" : ""
    end

    def title_is_user_populated?
      (form_advisory.persisted? || form_advisory.errors.any?).presence
    end

    # We should only show the dependabot alerts tab for the advisory being
    # displayed when at there is at least one vulnerable version range with an
    # ecosystem that is supported by dependency graph
    # This is because we need crucial information from dependency graph like the list and number
    # of repositories affected before alerts can be created/generated
    def show_dependabot_alerts_tab?
      advisory.vulnerable_version_ranges.any? do |vulnerable_version_range|
        ::AdvisoryDB::Ecosystems.dependency_graph_supported_names.include?(vulnerable_version_range.ecosystem)
      end
    end

    # The ability to convert an advisory to OSV is based on the associated
    # VVRs. Updates to VVRs will also update (touch) the advisory, so we can
    # cache this between updates to improve performance. The KV will be reset
    # by an after_commit hook on the advisory. We still set a reasonable TTL on
    # it just to ensure the KV is cleaned up on occasion for advisories that
    # don't get much traffic.
    def osv_compatible?
      compatible_key = advisory.github_kv_osv_compatible_key
      cached_compatible = AdvisoryDB::KV.store.get(compatible_key).value { nil }
      return (cached_compatible == "1" ? true : false) if cached_compatible.present?

      compatible = begin
        GitHub::OSV.ghsa_to_osv(advisory)
        true
      rescue AdvisoryDBToolkit::OSV::Transform::Error
        false
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        compatible_kv_value = compatible ? "1" : "0"
        AdvisoryDB::KV.store.set(compatible_key, compatible_kv_value, expires: 1.month.from_now)
      end

      compatible
    end

    # We should let users know when alerts are not supported for a particular advisory
    # This could be because the advisory has no vulnerable version range or is from an unsupported ecosystem
    # This method is only called when `show_dependabot_alerts_tab?` returns false
    def dependabot_alerts_not_supported_message
      unsupported_ecosystems = []

      advisory.vulnerable_version_ranges.each do |vulnerable_version_range|
        next if ::AdvisoryDB::Ecosystems.dependency_graph_supported_names.include?(vulnerable_version_range.ecosystem)

        unsupported_ecosystems << vulnerable_version_range.ecosystem
      end

      if advisory.vulnerable_version_ranges.blank?
        "Dependabot alerts are not supported on this advisory because it does not have a package from a supported ecosystem with an affected and fixed version."
      elsif unsupported_ecosystems.present?
        "Dependabot alerts are not supported on some or all of the ecosystems on this advisory."
      end
    end

    def details_tab
      !dependabot_alerts_tab
    end

    def render_description
      helpers.vulnerability_markdown(advisory, include_references: true)
    end

    def safe_repository_advisory_publisher
      @safe_repository_advisory_publisher ||= repository_advisory.publisher || User.ghost
    end

    def first_vulnerable_version_range
      advisory.vulnerable_version_ranges.first
    end

    def grouped_vulnerable_verson_ranges
      advisory.vulnerable_version_ranges.group_by do |range|
        [range.ecosystem, range.affects]
      end.sort_by do |(_ecosystem, affects), _ranges|
        affects
      end.map do |(ecosystem, affects), ranges|
        {
          ecosystem: ecosystem,
          package: affects,
          affected_versions: ranges.map(&:requirements),
          patched_versions: ranges.map(&:fixed_in),
        }
      end
    end

    def show_credits?
      return @show_credits if defined? @show_credits

      @show_credits = credits.any?
    end

    def show_closed_alerts?
      query.closed?
    end

    def credits
      return @credits if @credits

      advisory_credits = advisory.credits.accepted.preload(:recipient)

      @credits = RepositoryAdvisories::CreditView.for_advisory_credits(advisory_credits, current_user: current_user, viewer_can_manage: false)
    end

    def repository_alerts
      return @repository_alerts if defined? @repository_alerts

      @repository_alerts = repository_alerts_scope.includes(:repository).to_a

      GitHub::PrefillAssociations.prefill_batch_method(@repository_alerts, :current_dependency_update)

      @repository_alerts
    end

    def pull_request_for_alert(alert)
      alert.current_dependency_update&.pull_request
    end

    def dependabot_alerts_path(query:)
      urls.global_advisory_dependabot_alerts_path(advisory.ghsa_id, query: query)
    end

    def history_path
      urls.global_advisory_history_path(advisory.ghsa_id)
    end

    def organization_filters
      users = [current_user] + current_user.organizations.by_login
      filters = users.map do |user|
        {
          label: user.display_login,
          user: user,
          id: user.display_login,
          selected: query.qualifier_selected?(name: :user, value: user.login), # rubocop:disable GitHub/DoNotAllowLogin
          url: dependabot_alerts_path(query: query.toggle_qualifier(name: :user, value: user.display_login)),
        }
      end

      # Show selected filters at top of the list ]
      filters.partition { |filter| filter[:selected] }.flatten
    end

    def repository_type_filters
      filters = Search::Queries::DependabotAlertsQuery::REPOSITORY_TYPES.map do |type|
        {
          label: type.capitalize,
          selected: query.repository_type == type,
          url: dependabot_alerts_path(query: query.toggle_repository_type(value: type)),
        }
      end

      filters.unshift({
        label: "All",
        selected: query.repository_type.blank?,
        url: dependabot_alerts_path(query: query.toggle_repository_type(value: nil)),
      })
    end

    def sort_directions
      [
        { label: "Newest", query: "created-desc", default: true },
        { label: "Oldest", query: "created-asc" },
      ].map do |sort|
        selected = query.qualifier_selected?(name: :sort, value: sort[:query])
        selected ||= !query.contains_qualifier?(name: :sort) if sort[:default]
        {
          label: sort[:label],
          selected: selected,
          url: dependabot_alerts_path(query: query.replace_qualifier(name: :sort, value: selected ? nil : sort[:query])),
        }
      end
    end

    def feedback_url
      "#{GitHub.contact_support_url}/feedback?contact%5Bcategory%5D=security&contact%5Bsubject%5D=Product+feedback"
    end

    def contribute_analytic_attributes
      helpers.analytics_click_attributes(category: "Dependabot", action: "contribute_advisory", label: "ref_loc:advisory")
    end

    def timeline_items
      return @timeline_items if @timeline_items

      timeline_items = []
      timeline_items << { event: :published, time: advisory.published_at, icon: :shield, color: :green }
      timeline_items << { event: :updated, time: advisory.updated_at, icon: :clock } if advisory.updated_at != advisory.published_at
      timeline_items << { event: :reviewed, time: advisory.reviewed_at, icon: :"code-review" } if advisory.reviewed_at
      timeline_items << { event: :withdrawn, time: advisory.withdrawn_at, icon: :x } if advisory.withdrawn?
      timeline_items << { event: :nvd_published, time: advisory.nvd_published_at, icon: :shield, color: :green } if advisory.nvd_published_at?
      timeline_items << { event: :repo_published, time: repository_advisory.published_at, icon: :shield, color: :green } if has_readable_repository_advisory?

      @timeline_items = timeline_items.sort_by { |item| item[:time] }
    end

    def timeline_text(event)
      case event
      when :published
        "Published to the GitHub Advisory Database"
      when :updated
        "Last updated"
      when :reviewed
        "Reviewed"
      when :withdrawn
        "Withdrawn"
      else
        ""
      end
    end

    def timeline_badge_color(event)
      case event[:color]
      when :red
        "color-fg-on-emphasis color-bg-danger-emphasis"
      when :green
        "color-fg-on-emphasis color-bg-success-emphasis"
      when :purple
        "color-fg-on-emphasis color-bg-done-emphasis"
      else
        ""
      end
    end

    def repo_limit_exceeded?
      query.repo_limit_exceeded
    end
  end
end
