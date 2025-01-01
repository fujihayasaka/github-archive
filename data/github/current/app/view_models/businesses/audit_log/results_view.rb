# typed: true
# frozen_string_literal: true

class Businesses::AuditLog::ResultsView < ::AuditLog::ResultsView
  attr_reader :business

  def initialize(**args)
    super(args)
    @business = args[:business]
  end

  def tips
    @tips ||= Businesses::AuditLog::TipView.new(business: business, user: current_user)
  end

  def search_title
    if GitHub.single_business_environment?
      return "Recent events" if query.blank?
      return "No events found" if results.total_entries.zero?

      num_actors = results.map { |res| res[:actor] }.uniq.count
      actors = helpers.pluralize(num_actors, "actor")
      events = helpers.pluralize(results.total_entries, "event")

      "#{events} by #{actors}"
    else
      super
    end
  end

  def can_show_ip?
    return true if GitHub.enterprise?
    return @can_show_ip if defined?(@can_show_ip)
    @can_show_ip = business&.can_enable_audit_log_ip_disclosure? && business&.source_ip_disclosure_enabled?
  end

  def can_view_sso?
    business.present? && GitHub.flipper[:audit_sso_disclosure].enabled?(business)
  end

  def search_path(options = {})
    query = {}
    query[:q] = build_query_param(options) if options.present?
    urls.settings_audit_log_enterprise_path(business, query)
  end

  def search_path_query(options)
    urls.settings_audit_log_enterprise_path(business, options)
  end

  def suggestions_path
    urls.settings_audit_log_suggestions_enterprise_path(business)
  end

  def support_url
    "#{GitHub.help_url}/admin/monitoring-activity-in-your-enterprise/reviewing-audit-logs-for-your-enterprise/searching-the-audit-log-for-your-enterprise"
  end

  def suggestable_qualifiers
    [
      { value: "action:", description: "filter by action" },
      { value: "actor:", description: "filter by author" },
      { value: "country:", description: "filter by country" },
      { value: "created:", description: "filter by date" },
      { value: "hashed_token:", description: "filter by access token" },
      { value: "operation:", description: "filter by operation" },
      { value: "org:", description: "filter by organization" },
      { value: "token_id:", description: "filter by token ID" },
      { value: "repo:", description: "filter by repository" },
      { value: "user:", description: "filter by user" },
    ] + flagged_suggestable_qualifiers
  end

  def flagged_suggestable_qualifiers
    qualifiers = []
    qualifiers << { value: "ip:", description: "filter by IP address" } if can_show_ip?
    qualifiers
  end

  def export_path
    urls.settings_audit_log_export_enterprise_path(business, format: :json)
  end

  def export_git_event_path
    urls.settings_audit_log_git_event_export_enterprise_path(business, format: :json)
  end

  def show_export_all?
    audit_logs? && GitHub.audit_log_export_enabled?
  end

  def filters_partial
    "businesses/audit_log/search_filters"
  end

  def normalize(entries)
    # we don't want to call the `.reject` filtering of the allowlist again for an EMU business
    if GitHub.single_business_environment? || business&.enterprise_managed_user_enabled?
      super
    else
      AuditLogEntry.for_businesses(entries)
    end
  end

  def next_page_link
    options = {
      q: query,
      after: after,
      before: before,
      slug: business.slug,
      page: page.to_i + 1,
    }
    urls.settings_audit_log_enterprise_path(options)
  end

  def prev_page_link
    options = {
      q: query,
      after: after,
      before: before,
      slug: business.slug,
      page: page.to_i - 1,
    }
    urls.settings_audit_log_enterprise_path(options)
  end

  def enterprise_account_management_query
    "action:business"
  end

  def hook_activity_query
    "action:hook action:pre_receive_hook"
  end

  def security_management_query
    "action:public_key action:security_key action:two_factor_authentication"
  end

  def pat_activity_query
    "action:personal_access_token"
  end

  def copilot_activity_query
    "action:copilot"
  end

  private

  # Private: The business scoped audit log ElasticSearch query.
  #
  # Returns Hash
  def es_query
    query_hash = {
      current_user: current_user,
      phrase: query,
      page: page,
      after: after,
      before: before,
      feature_flags: feature_flags,
      per_page: 25,
    }

    query_hash[:business_id] = business.id unless GitHub.single_business_environment?

    query_hash
  end
end
