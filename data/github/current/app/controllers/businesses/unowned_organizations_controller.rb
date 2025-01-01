# typed: strict
# frozen_string_literal: true

class Businesses::UnownedOrganizationsController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :provisioning_feature_flag_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: %i(index)

  sig { void }
  def index
    organizations = this_business.orphaned_organizations
      .includes(:saml_provider, :business)
      .paginate(page: current_page)

    render "businesses/organizations/orphaned_organizations", locals: {
      organizations: organizations,
    }
  end

  sig { void }
  def update
    organization = this_business.organizations.find_by(login: login_from_param)

    if organization.admins.any?
      flash[:error] = "This organization already has at least one active owner."
      redirect_to enterprise_organizations_path(this_business)
    else
      # Either update their membership to admin or add them as a new admin
      if organization.direct_member?(current_user)
        organization.update_member(current_user, action: :admin)
      else
        organization.add_admin(current_user)
      end

      flash[:notice] = "Successfully added #{current_user} as an owner of the '#{organization}' organization."
      redirect_to enterprise_organizations_path(this_business)
    end
  end

  private

  sig { void }
  def provisioning_feature_flag_required
    render_404 unless GitHub.flipper[:enterprise_idp_provisioning].enabled?(this_business)
  end

  sig { returns(String) }
  memoize def login_from_param
    params[:login]
  end
end
