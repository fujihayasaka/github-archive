# typed: true
# frozen_string_literal: true

class AuditLog::IndexPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  class MissingFiltersPartialError < StandardError; end

  # View model attributes
  attr_reader :query
  attr_reader :valid_query
  attr_reader :page
  attr_reader :after
  attr_reader :before
  attr_reader :git_export_enabled
  attr_reader :export_logs_enabled
  attr_reader :feature_flags
  attr_reader :cap_filter
  alias_method :git_export_enabled?, :git_export_enabled
  alias_method :export_logs_enabled?, :export_logs_enabled

  alias_method :valid_query?, :valid_query

  def after_initialize

  end

  def page_title

  end

  def page_class

  end

  # Public: Whether we're actively searching for something beyond the default
  # results view.
  #
  # Returns a Boolean
  def active_search?
    query.present?
  end

  def suggestions_path

  end

  def search_path
    raise NotImplementedError
  end

  def filters_partial
    raise MissingFiltersPartialError, "filters_partial is not set for #{self.class}"
  end

  def build_query_param(replace = {}, append = [])
    components = Search::Queries::AuditLogQuery.parse(query)

    replace.each do |key, value|
      if component = components.assoc(key)
        if value
          component[1] = value
        else
          components.delete(component)
        end
      elsif value
        components << [key, value]
      end
    end

    components.concat(append)

    Search::Queries::AuditLogQuery.stringify(components)
  end

  def tips
    raise NotImplementedError
  end

  def suggestable_qualifiers
    [
      { value: "action:", description: "filter by action" },
      { value: "country:", description: "filter by country" },
      { value: "created:", description: "filter by created date" },
      { value: "operation:", description: "filter by operation" },
      { value: "org:", description: "filter by organization" },
      { value: "repo:", description: "filter by repository" },
    ]
  end

  def export_path
    raise NotImplementedError
  end

  def export_git_event_path
    raise NotImplementedError
  end

  def user_time_now(add: 0)
    zone = current_user&.time_zone || Time.zone
    (zone.now + add).strftime("%Y-%m-%dT%H:%M")
  end

  private

  # Private: The organization scoped audit log ElasticSearch query.
  #
  # Returns Hash
  def es_query
    raise NotImplementedError
  end

  def search_query
    @search_query ||= Audit::Driftwood::Query.new_org_business_query(es_query)
  end

  def page_params(after: "", before: "")
    pg_params = []
    pg_params << "q=#{query}" if active_search?
    pg_params << "after=#{after}" unless after.blank?
    pg_params << "before=#{before}" unless before.blank?
    if pg_params.any?
      "?#{pg_params.join('&')}"
    end
  end

  def audit_log_record_for_ids(records_by_id, id)
    if id.is_a?(Array)
      id.each { |i| return records_by_id[i] if records_by_id[i] }
      nil
    else
      records_by_id[id]
    end
  end
end
