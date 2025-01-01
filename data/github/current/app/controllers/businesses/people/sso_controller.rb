# typed: true
# frozen_string_literal: true

class Businesses::People::SsoController < Businesses::BusinessController
  before_action :read_enterprise_sso_or_scim_required
  before_action :sso_enabled_required
  before_action :person_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    organization_count, team_count, installation_count = if GitHub.enterprise?
      [
        person.filter_organizations(current_user).count,
        person.filter_teams(current_user).count,
        0
      ]
    elsif business_user_account.present?
      [
        business_user_account.enterprise_organizations(current_user).count,
        business_user_account.enterprise_teams.count,
        business_user_account.user_enterprise_installations.count
      ]
    else
      [0, 0, 0]
    end
    outside_collaborator_repositories_count = \
      person.outside_collaborator_repositories(business: this_business)&.count.to_i

    view = create_view_model(
      Sso::ShowView,
      target: this_business,
      member: person,
    )
    render "businesses/people/sso", locals: {
      user_account: business_user_account,
      user: person,
      organization_count: organization_count,
      team_count: team_count,
      installation_count: installation_count,
      outside_collaborator_repositories_count: outside_collaborator_repositories_count,
      view: view,
    }
  end

  private

  memoize def business_user_account
    person.business_user_accounts.find_by(business_id: this_business.id)
  end
end
