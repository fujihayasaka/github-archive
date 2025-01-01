# typed: strict
# frozen_string_literal: true

class Businesses::DataPacksController < Businesses::BusinessController
  extend T::Sig

  before_action :ensure_business_can_self_serve
  before_action :require_business_has_orgs, only: :index
  before_action :business_access_required
  before_action only: [:index] do
    T.bind(self, Businesses::DataPacksController)
    check_trade_compliance(target: this_business, feature_type: :cost_management)
  end
  before_action only: [:update] do
    T.bind(self, Businesses::DataPacksController)
    check_trade_compliance(target: this_business, feature_type: :cost_management, sdn_redirect: true)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    target = this_business.organizations.first
    data_pack_change = Billing::PlanChange::DataPackChange.new(target, total_packs: target.data_packs)
    render "businesses/data_packs/index", locals: {
      data_pack_change: data_pack_change,
      target: target,
    }
  end

  sig { void }
  def update
    target = this_business.organizations.find_by(login: params[:organization])
    total_packs = target.data_packs + asset_status_params.fetch(:delta_packs, 0).to_i

    data_pack_updater = Billing::DataPackUpdater.new(target, total_packs: total_packs, actor: current_user)

    if data_pack_updater.update
      flash[:notice] = "Successfully updated your data plan. Thanks!"
      redirect_to settings_billing_enterprise_path(this_business)
    else
      flash[:error] = data_pack_updater.error
      redirect_to :back
    end
  end

  private

  sig { returns(ActionController::Parameters) }
  def asset_status_params
    params.require(:asset_status).permit(:delta_packs)
  end

  sig { void }
  def ensure_business_can_self_serve
    if !this_business.can_self_serve?
      flash[:error] = "Please contact your GitHub Enterprise account representative to add more data packs to your plan."
      redirect_to settings_billing_enterprise_path(this_business)
    end
  end

  sig { void }
  def require_business_has_orgs
    if this_business.organizations.empty?
      flash[:error] = "Please add an organization to your enterprise to purchase data packs."
      redirect_to settings_billing_enterprise_path(this_business)
    end
  end

  helper_method :allowed_to_purchase_data_packs?
  sig { returns(T::Boolean) }
  def allowed_to_purchase_data_packs?
    !this_business.has_commercial_interaction_restriction?(feature_type: :cost_management) &&
    !current_user.has_commercial_interaction_restriction?(feature_type: :cost_management)
  end
end
