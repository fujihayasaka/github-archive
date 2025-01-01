# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::DowngradeController < Stafftools::Businesses::BillingController
  include Stafftools::Businesses::TradeCompliance::SharedControllerMethods

  before_action :ensure_target_not_restricted

  sig { void }
  def update
    return redirect_with_error("This enterprise is not billed by invoice.") unless this_business.invoiced?
    return redirect_with_error("This enterprise has organizations associated with it. Please remove the organizations first.") if has_organizations?

    update_business
    redirect_to stafftools_enterprise_path
  end

  private

  sig { returns(T::Boolean) }
  def has_organizations?
    this_business.organizations.any?
  end

  sig { params(message: String).void }
  def redirect_with_error(message)
    flash[:error] = message
    redirect_to stafftools_enterprise_path(this_business)
  end

  sig { void }
  def update_business
    this_business.seats = 0
    this_business.support_plan = Configurable::SupportPlan::STANDARD unless this_business.support_plan == Configurable::SupportPlan::EDUCATION

    if this_business.save
      if this_business.enterprise_agreements.active.any?
        this_business.enterprise_agreements.active.each(&:ended!)
      end
      this_business.set_advanced_security_seats_for_entity(seats: 0, actor: T.must(current_user), is_stafftools_action: true)
      this_business.mark_advanced_security_as_not_purchased_for_entity(actor: T.must(current_user))
      this_business.staff_notes.create(user: current_user, note: "Account billing downgraded due to dunning")
      flash[:notice] = "Successfully downgraded billing for #{this_business.name}."
    else
      flash[:error] = this_business.errors.full_messages.to_sentence
    end
  end
end
