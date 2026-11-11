# typed: true
# frozen_string_literal: true

class Businesses::AuditLog::IndexPageView < ::AuditLog::IndexPageView
  attr_reader :business

  def initialize(**args)
    super(args)
    @business = args[:business]
  end

  def results_path
    options = {
      q: query,
      after: after,
      before: before,
      slug: business.slug,
      page: page,
    }
    urls.settings_audit_log_results_enterprise_path(options)
  end

  def export_path
    urls.settings_audit_log_export_enterprise_path(business, format: :json)
  end

  def export_git_event_path
    urls.settings_audit_log_git_event_export_enterprise_path(business, format: :json)
  end

  def driftwood_streaming_enabled?
    GitHub.driftwood_streaming_enabled?
  end

  def enterprise_retention_enabled?
    GitHub.audit_log_es_logger_enabled?
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
      per_page: 15,
    }

    query_hash[:business_id] = business.id unless GitHub.single_business_environment?

    query_hash
  end
end
