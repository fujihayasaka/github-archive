# typed: strict
# frozen_string_literal: true

class Stafftools::Billing::PaymentMethodsController < StafftoolsController
  include Stafftools::TradeCompliance::SharedControllerMethods

  before_action :ensure_billing_enabled
  before_action :ensure_billable_entity

  before_action only: [:destroy] do
    T.bind(self, Stafftools::Billing::PaymentMethodsController)
    ensure_target_not_restricted(feature_type: :cost_management)
  end

  sig { void }
  def destroy
    if target.remove_all_payment_methods(current_user)
      flash[:notice] = "Successfully removed all payment methods."
    else
      flash[:error] = "One or more payment methods were not removed."
    end

    redirect_to :back
  end


  private

  sig { void }
  def ensure_billable_entity
    render_404 unless billable_entity
  end

  sig { override.returns(Billing::Types::Account) }
  def target
    T.must(billable_entity)
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
  memoize def billable_entity
    case params[:target_type]
    when "User", "Organization"
      User.find_by(id: params[:target_id])
    when "Business"
      Business.find_by(id: params[:target_id])
    end
  end
end
