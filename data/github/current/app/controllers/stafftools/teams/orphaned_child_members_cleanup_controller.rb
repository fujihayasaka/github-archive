# typed: true
# frozen_string_literal: true

# Stafftools-only entry point for sweeping orphaned indirect
# ("child team member") `Ability` rows from a single team. Backstop for
# the bug fixed in #432887 / PCR 2025-12-22 -- a re-parented child team
# can leave behind `priority: indirect` rows whose parent ability points
# at a team that is no longer a descendant of this team.
#
# Safe to invoke whether or not the team currently has descendants: the
# job only removes rows whose parent ability falls outside the team's
# current descendant set, so legitimate inherited memberships are left
# alone.
class Stafftools::Teams::OrphanedChildMembersCleanupController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_team_exists

  layout "layouts/stafftools/organization/security"

  def create
    CleanUpOrphanedChildTeamMembersJob.perform_later(this_team.id, actor_id: current_user&.id)
    flash[:notice] = "Queued cleanup of orphaned child team members for #{this_team.name}."

    redirect_to members_stafftools_user_team_path(this_team.organization, this_team)
  end
end
