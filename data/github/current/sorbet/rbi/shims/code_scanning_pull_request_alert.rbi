# typed: strict
# frozen_string_literal: true

class SecurityOverviewAnalytics::CodeScanningPullRequestAlert
  sig { returns(T.nilable(String))}
  def total_alerts_resolved; end

  sig { returns(T.nilable(String)) }
  def total_alerts_open; end
end
