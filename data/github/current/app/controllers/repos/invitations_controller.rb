# typed: true
# frozen_string_literal: true

class Repos::InvitationsController < AbstractRepositoryController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,

    def new
      return render_404 unless current_repository.organization&.feature_enabled?(:add_people_select_panel)

      invitee_id = params[:invitee_id]
      invitee = if invitee_id.include?("@")
        User.find_by_email(invitee_id)
      else
        if invitee_class == Team && check_business_teams?
          Orgs.domain.teams.find_team_in_organization(
            business_id: current_repository.organization.business&.id,
            organization_id: current_repository.organization.id,
            team_id: invitee_id.to_i)
        else
          invitee_class.find(invitee_id)
        end
      end

      return render_404 if invitee.nil? && invitee_class == Team

      if invitee.nil? || invitee.is_a?(User) && invitee.emails.find { |e| e.email == invitee_id }&.private?
        invitee = invitee_class.new(email: invitee_id)
      end

      render Repositories::AccessManagement::ChooseRoleComponent.new(
        member: invitee,
        repository: current_repository,
      )
    end

  private

  def invitee_class
    case params[:invitee_type]
    when "team"
      Team
    else
      User
    end
  end

  def authorized?
    logged_in? && current_repository&.adminable_by?(current_user)
  end

  def check_business_teams?
    current_repository.organization&.business&.feature_enabled?(:enterprise_teams_org_roles)
  end
end
