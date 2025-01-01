# typed: true
# frozen_string_literal: true

class Businesses::Organizations::SsoController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required
  before_action :require_current_organization
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    if !(this_business.saml_sso_enabled? && this_business.feature_enabled?(:enterprise_idp_provisioning))
      return render_404
    end

    identities = this_business
      .saml_provider
      .external_identities_for_organization(current_organization)
      .includes(user: :business_user_accounts)
      .paginate(page: current_page, per_page: PAGE_SIZE)

    view = create_view_model(
      Sso::ShowView,
      target: this_business,
      member: current_organization,
      business_user_account: nil,
      linked_identity_list: identities,
    )
    render "businesses/organizations/sso", locals: { view: view }
  end
end
