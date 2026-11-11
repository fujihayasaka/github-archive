# typed: strict
# frozen_string_literal: true

class Stafftools::Users::TradeComplianceController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods
  include Contacts::SharedControllerMethods

  before_action :ensure_user_exists
  before_action :ensure_billing_enabled
  before_action :dotcom_required

  javascript_bundle :billing, only: [:show, :create]
  layout :overview_layout

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::Users::TradeComplianceController#update",
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show, :update]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    trade_controls_view = Stafftools::User::TradeControlsView.new(user: this_user)
    render "stafftools/users/trade_compliance/show", locals: { view: trade_controls_view }
  end

  sig { void }
  def create
    mode = params[:mode]
    if mode == "show"
      this_user.billing_contact.instrument :view, actor: current_user, reason: "Billing info viewed by staff"
    end
    edit_mode = Stafftools::AccessControl.authorized?(current_user, { controller: self.class.name, action: :update }) && mode == "edit"
    trade_controls_view = Stafftools::User::TradeControlsView.new(
      user: this_user,
      show_billing_info: mode == "show",
      edit_mode: edit_mode
    )
    render "stafftools/users/trade_compliance/show", locals: { view: trade_controls_view }
  end

  sig { void }
  def update
    billing_contact = target.billing_contact
    if billing_contact.has_update_trade_restrictions?
      flash[:error] = "Cannot update billing information due to trade restrictions."
      redirect_to stafftools_user_trade_compliance_path(this_user)
      return
    end

    if update_billing_contact(skip_redirect: true)
      flash[:notice] = "Successfully updated billing information."
      redirect_to stafftools_user_trade_compliance_path(this_user)
    else
      flash[:error] = "Failed to update billing information."
      redirect_to stafftools_user_trade_compliance_path(this_user, edit_mode: true)
    end
  end

  protected

  sig { returns(User) }
  def actor
    current_user
  end

  sig { override.returns(T.any(User, Organization)) }
  def target
    this_user
  end

  private

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
      :postal_code
    )
  end
end
