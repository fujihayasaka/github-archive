# typed: false
# frozen_string_literal: true

module AbuseReportsHelper
  def toggle_resolved_path(resolved_filter, repo)
    if resolved_filter == "RESOLVED"
      unresolve_abuse_reports_path(repo.owner_display_login, repo)
    else
      resolve_abuse_reports_path(repo.owner_display_login, repo)
    end
  end

  def resolve_action_word(resolved_filter)
    resolved_filter == "RESOLVED" ? "unresolved" : "resolved"
  end
end
