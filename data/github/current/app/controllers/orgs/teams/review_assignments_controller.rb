# typed: true
# frozen_string_literal: true

class Orgs::Teams::ReviewAssignmentsController < Orgs::Controller
  before_action :login_required
  before_action :organization_read_required
  before_action :admin_on_team_required
  before_action :this_team_required
  before_action :mask_analytics_data

  javascript_bundle :settings
  stylesheet_bundle :orgs
  stylesheet_bundle :settings

  # check whether organization invitations have been rate limited; but do not
  # enforce rate limiting in this controller.
  include Orgs::Invitations::RateLimiting

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:edit]

  def edit
    render Organizations::Teams::ReviewAssignmentComponent.new(team: this_team), layout: "team"
  end

  def update
    unless this_team.updatable_by?(current_user)
      flash[:error] = "#{current_user} does not have permission to update this team."
      return redirect_to edit_team_review_assignment_path(this_organization, this_team)
    end

    this_team.review_request_delegation_notify_team = !params[:disable_notify_team]
    auto_assign_enabled = !!params[:review_assignment]

    excluded_member_ids = params[:excluded_members] || []
    ReviewRequestDelegationExcludedMember.update_excluded_team_members(
      team: this_team,
      excluded_member_ids: excluded_member_ids,
      exclude_team_members: !!params[:exclude_team_members]
    )

    if auto_assign_enabled
      unless !!params[:algorithm] && !!params[:team_member_count]
        flash[:error] = "Algorithm and team member count needed when enabling."
        return redirect_to edit_team_review_assignment_path(this_organization, this_team)
      end

      this_team.review_request_delegation_enabled = true
      this_team.review_request_delegation_algorithm = params[:algorithm]
      this_team.review_request_delegation_member_count = params[:team_member_count].to_i
      this_team.review_request_delegation_remove_team_request = !!params[:remove_team_request]
      this_team.review_request_delegation_include_child_team_members = !!params[:include_child_team_members]
      this_team.review_request_delegation_count_members_already_requested = !!params[:count_members_already_requested]
    else
      this_team.review_request_delegation_enabled = false
    end

    if this_team.save
      flash[:notice] = "You've successfully updated the team's code review settings."
      render Organizations::Teams::ReviewAssignmentComponent.new(team: this_team), layout: "team"
    else
      flash[:error] = this_team.errors.full_messages.join(", ")
      redirect_to edit_team_review_assignment_path(this_organization, this_team)
    end
  end

  private

  def mask_analytics_data
    override_analytics_location "/orgs/<org-login>/teams/<team-name>/edit/review_assignment"
    strip_analytics_query_string
  end
end
