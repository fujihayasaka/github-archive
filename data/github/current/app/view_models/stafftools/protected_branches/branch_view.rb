# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class Stafftools::ProtectedBranches::BranchView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :branch

  def dismissal_actors
    user_allowances, team_allowances = branch.review_dismissal_allowances.partition { |allowance| allowance.actor.is_a?(User) }

    users = User.where(id: user_allowances.map(&:actor_id))
    teams = Team.where(id: team_allowances.map(&:actor_id))

    {
      users: users,
      teams: teams,
    }
  end

  def dismissal_users_count
    dismissal_actors[:users].size
  end

  def dismissal_teams_count
    dismissal_actors[:teams].size
  end

  def show_dismissal_actors_list?
    dismissal_users_count > 0 || dismissal_teams_count > 0
  end

  def authorized_actors
    @authorized_actors ||= begin
      integration_installations = branch.authorized_integration_installations.includes(:integration)

      {
        users: branch.authorized_users,
        teams: branch.authorized_teams,
        integration_installations: integration_installations,
      }
    end
  end

  def authorized_users_count
    authorized_actors[:users].size
  end

  def authorized_teams_count
    authorized_actors[:teams].size
  end

  def authorized_integration_installations_count
    authorized_actors[:integration_installations].size
  end

  def show_authorized_actors_list?
    authorized_users_count > 0 || authorized_teams_count > 0 || authorized_integration_installations_count > 0
  end

  def authorized_actors_text
    "#{helpers.pluralize(authorized_users_count, "user")}, "\
    "#{helpers.pluralize(authorized_teams_count, "team")}, "\
    "#{helpers.pluralize(authorized_integration_installations_count, "app")}"
  end

  def restricted_dismissal_text
    "#{helpers.pluralize(dismissal_users_count, "user")}, #{helpers.pluralize(dismissal_teams_count, "team")}"
  end

  def status_check_audit_link(status_check)
    query =
      if GitHub.driftwood_ade_queries_enabled?
        <<~KQL
          webevents
          | where repo_id == #{branch.repository_id}
          | where action startswith "required_status_check."
          | where data.context == "#{status_check.context}"
          | where data.protected_branch_name == "#{branch.name}"
        KQL
      else
        "repo_id:#{branch.repository_id} action:required_status_check.* data.context:\"#{status_check.context}\" data.protected_branch_name:\"#{branch.name}\""
      end

    urls.stafftools_audit_log_path(query: query)
  end

  def octicon_x
    helpers.octicon("x", class: "color-fg-danger")
  end

  def octicon_check
    helpers.octicon("check", class: "color-fg-success")
  end

  # Returns a checkmark octicon, or a X octicon, depending on if the
  # boolean provided is true or false.
  #
  # Example:
  #   octicon_for_boolean(branch.admin_enforced?)
  #
  # boolean - A Boolean.
  def octicon_for_boolean(boolean)
    boolean ? octicon_check : octicon_x
  end
end
