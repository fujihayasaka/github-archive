# typed: true
# frozen_string_literal: true

class Stafftools::AuditLogTeaserController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_account_is_user

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    fetch_audit_log_teaser this_user_query

    render \
      partial: "stafftools/audit_log",
      locals: {
        query: @query,
        logs: @logs,
        more_results: @more_results,
      }
  end

  private

  ORG_AUDIT_EVENTS = %w(
      action:org.invite_member
      action:org.cancel_invitation
      action:org.add_member
      action:org.update_member
      action:org.remove_member
      action:org.restore_member
      action:org.add_billing_manager
      action:org.remove_billing_manager
    )

  def kql_actions(actions)
    actions.map { |a| "'#{a.gsub("action:", "")}'" }.join(", ")
  end

  def this_user_query
    if driftwood_ade_query?(current_user)
      "webevents | where user_id == #{this_user.id} | where action in (#{kql_actions(ORG_AUDIT_EVENTS)})"
    else
      "user_id:#{this_user.id} AND (#{ORG_AUDIT_EVENTS.join(" OR ")})"
    end
  end
end
