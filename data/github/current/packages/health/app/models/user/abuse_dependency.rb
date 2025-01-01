# typed: false
# frozen_string_literal: true

module User::AbuseDependency
  extend ActiveSupport::Concern

  class_methods do
    ABUSE_TYPE_WITH_ACTION = {
      spam: "staff.mark_as_spammy",
      suspension: "user.suspend",
    }

    def timestamps_for_abuse_type_by_user_id(abuse_type, user_ids, viewer: nil)
      result = {}
      return result unless GitHub.spamminess_check_enabled?
      return result if user_ids.empty? || !ABUSE_TYPE_WITH_ACTION[abuse_type].present?

      action = ABUSE_TYPE_WITH_ACTION[abuse_type]
      search_conditions = user_ids.map { |user_id| "user_id:#{user_id} OR org_id:#{user_id}" }.join(" OR ")
      phrase = "action:#{action} (#{search_conditions})"
      if GitHub.driftwood_ade_queries_enabled?
        user_list = user_ids.join(",")
        phrase = <<~KQL
          webevents
          | where action == "#{action}"
          | where user_id in (#{user_list}) or org_id in (#{user_list})
        KQL
      end
      query = Audit::Driftwood::Query.new_stafftools_query(phrase: phrase, raw: true, current_user: viewer)
      audit_log_results = AuditLogEntry.new_from_array(query.execute)
      audit_log_results.each do |audit_log_result|
        user_id = audit_log_result.user_id || audit_log_result.org_id
        timestamp = audit_log_result.created_at
        result[user_id] ||= timestamp
        result[user_id] = timestamp if timestamp > result[user_id]
      end

      result
    end

    def user_ids_marked_before(abuse_type, user_ids, cutoff_time:, viewer: nil)
      marked_timestamp_by_user_id = timestamps_for_abuse_type_by_user_id(abuse_type, user_ids, viewer: viewer)
      user_ids.select do |user_id|
        timestamp = marked_timestamp_by_user_id[user_id]
        timestamp && timestamp < cutoff_time
      end
    end
  end

  # Public: Has this user ever had a session from a known anonymizing proxy
  # (e.g. Tor)?
  #
  # Returns a Boolean.
  def anonymizing_proxy_user?
    !!has_used_anonymizing_proxy
  end
end
