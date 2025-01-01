# typed: true
# frozen_string_literal: true

class Orgs::People::SsoController < Orgs::Controller
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :login_required
  before_action :organization_admin_required
  before_action :sso_enabled_required

  javascript_bundle :organizations

  include RepositoryControllerMethods

  # Shows any linked ExternalIdentity information from SAML SSO as well
  # as any authorized personal access tokens the user has if the organization
  # has SAML SSO enforced across the org.
  def index
    return render_404 if person.nil?

    override_analytics_location "/orgs/<org-login>/people/<user-name>/sso"

    view = create_view_model(
      Sso::ShowView,
      target: this_organization,
      member: person,
      business_user_account: nil,
    )
    render "orgs/people/sso", locals: { view: view }
  end
end
