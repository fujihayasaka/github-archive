# typed: strict
# frozen_string_literal: true

module ProjectsClassicSunset::ProjectsClassicSunsetControllerActions
  extend T::Helpers
  include GitHub::Memoizer
  include OrganizationParamsHelper

  requires_ancestor { ApplicationController }

  # Taken from OrganizationsHelper
  sig { returns(T.nilable(Organization)) }
  memoize def current_organization
    if id = org_login_param || T.unsafe(self).params[:id]
      if T.unsafe(self).logged_in?
        find_org_accessible_by_current_user(id)
      end
    end
  end

  # Taken from OrganizationsHelper
  sig { params(org_login: String).returns(T.nilable(Organization)) }
  def find_org_accessible_by_current_user(org_login)
    org = Organization.find_by_login(org_login)
    org if org&.direct_or_team_member?(T.unsafe(self).current_user) ||
      org&.adminable_by?(T.unsafe(self).current_user) ||
      org&.billing_manager?(T.unsafe(self).current_user)
  end

  sig { void }
  def render_404_unless_projects_classic_ui_enabled_for_current_user
    T.bind(self, T.all(ApplicationController, ProjectsClassicSunset::ProjectsClassicSunsetControllerActions))
    user = T.let(current_user, T.nilable(User))
    return unless user

    repo = T.let(current_repository, T.nilable(Repository))
    org = T.let(current_organization, T.nilable(Organization))

    render_404 unless ProjectsClassicSunset.projects_classic_ui_enabled?(user, org: repo.present? ? repo.organization : org)
  end
end
