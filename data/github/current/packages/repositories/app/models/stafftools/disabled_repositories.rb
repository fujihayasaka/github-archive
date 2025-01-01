# typed: true
# frozen_string_literal: true

class Stafftools::DisabledRepositories
  extend AuditLogHelper

  def self.dmca_takedowns(user, current_user = nil)
    phrase = "action:staff.disable_repo data.reason:dmca user_id:#{user.id}"
    if driftwood_ade_query?(current_user)
      phrase = <<~KQL
        webevents
        | where action == "staff.disable_repo"
        | where data.reason == "dmca"
        | where user_id == #{user.id}
      KQL
    end
    query = Audit::Driftwood::Query.new_stafftools_query(
      phrase: phrase,
      current_user: user,
    )
    results = query.execute.results
  end

  def self.dmca_restores(user, current_user = nil)
    phrase = "action:staff.enable_repo user_id:#{user.id} from:\"stafftools/dmca_takedowns#destroy\""
    if driftwood_ade_query?(current_user)
      phrase = <<~KQL
        webevents
        | where action == "staff.enable_repo"
        | where user_id == #{user.id}
        | where data.from == "stafftools/dmca_takedowns#destroy"
      KQL
    end
    query = Audit::Driftwood::Query.new_stafftools_query(
      phrase: phrase,
      current_user: user,
    )
    query.execute.results
  end
end
