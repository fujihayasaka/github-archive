# typed: true
# frozen_string_literal: true

class Orgs::People::RepositoryPermissionsController < Orgs::Controller
  include ActionView::Helpers::TextHelper
  include EnterpriseManagedUsersHelper
  include RepositoryControllerMethods

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  before_action :login_required
  before_action :organization_admin_required
  before_action only: :destroy do
    T.bind(self, Orgs::People::RepositoryPermissionsController)
    ensure_trade_restrictions_allows_org_member_management(fallback_location: org_people_url(this_organization))
  end

  javascript_bundle :organizations

  def show
    # We check this instead of pullable_by? because there are cases where the
    # person may have access to the repo but the logged-in user shouldn't know
    # about it.
    if this_organization.visible_repositories_for(person).exclude?(current_repository)
      return render_404
    end

    override_analytics_location "/orgs/<org-login>/people/<user-name>/repositories/<user-name>/<repo-name>"
    if affiliated_with_org?(person)
      view = create_view_model(
        Orgs::People::RepositoryPermissionsView,
        organization: this_organization,
        person: person,
        repository: current_repository,
      )
      render "orgs/people/repository_permissions", locals: { view: view }
    else
      render_404
    end
  end

  def destroy
    if affiliated_with_org?(person)
      permissions = Organization::RepositoryPermissions.new(current_repository, person)

      if params[:active_only] == "1"
        permission_after_revoking = permissions.permission_after_revoking_active
        permissions.revoke_active(actor: current_user)
      else
        permission_after_revoking = nil
        permissions.revoke_all(actor: current_user)
      end

      if permission_after_revoking.present?
        flash[:notice] = "Decreased #{person.display_login}'s access to #{current_repository.name_with_display_owner}."
        redirect_to repository_permissions_path(this_organization, person, current_repository.owner, current_repository)
      else
        flash[:notice] = "Removed #{person.display_login}'s access to #{current_repository.name_with_display_owner}."

        if affiliated_with_org?(person)
          redirect_to org_person_path(this_organization, person)
        else
          redirect_to org_people_path(this_organization)
        end
      end
    else
      render_404
    end
  end

  private

  def affiliated_with_org?(person)
    return false if person.nil?
    return true if this_organization.direct_or_team_member?(person)

    # If the person is not a direct or team member of the org, they're only
    # affiliated with the org if they're a collaborator on at least one of the
    # org's repositories.
    this_organization.repositories_associated_with(person).any?
  end
end
