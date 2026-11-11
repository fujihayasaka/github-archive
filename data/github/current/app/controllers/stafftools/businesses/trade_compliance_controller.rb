# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::TradeComplianceController < Stafftools::Businesses::BusinessBaseController
  include Contacts::SharedControllerMethods
  before_action :business_required
  before_action :ensure_billing_enabled
  before_action :dotcom_required

  javascript_bundle :billing, only: [:show, :create]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::Businesses::TradeComplianceController#update",
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show, :update]

  sig { void }
  def show
    render "stafftools/businesses/trade_compliance/show", locals: { business: this_business, }
  end

  sig { void }
  def create
    mode = params[:mode]
    if mode == "show"
      this_business.billing_contact.instrument :view, actor: current_user, reason: "Billing info viewed by staff"
    end
    edit_mode = Stafftools::AccessControl.authorized?(current_user, { controller: self.class.name, action: :update }) && mode == "edit"
    render "stafftools/businesses/trade_compliance/show", locals: { business: this_business, show_billing_info: mode == "show", edit_mode: edit_mode }
  end

  sig { void }
  def update
    billing_contact = this_business.billing_contact
    if billing_contact.has_update_trade_restrictions?
      flash[:error] = "Cannot update billing information due to trade restrictions."
      redirect_to stafftools_enterprise_trade_compliance_path(this_business)
      return
    end

    if update_billing_contact(skip_redirect: true)
      flash[:notice] = "Successfully updated billing information."
      redirect_to stafftools_enterprise_trade_compliance_path(this_business)
    else
      flash[:error] = "Failed to update billing information."
      redirect_to stafftools_enterprise_trade_compliance_path(this_business, edit_mode: true)
    end
  end

  private

  sig { override.returns(Business) }
  def target
    this_business
  end

  sig { returns(ActionController::Parameters) }
  def billing_contact_params
    params.require(:billing_contact).permit(
      :first_name,
      :last_name,
      :middle_name,
      :entity_name,
      :address1,
      :address2,
      :city,
      :region,
      :country_code,
      :postal_code,
      :vat_code
    )
  end
end
