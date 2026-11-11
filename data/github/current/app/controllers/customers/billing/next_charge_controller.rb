# typed: true
# frozen_string_literal: true

class Customers::Billing::NextChargeController < Customers::BillingController
  include ApplicationController::VerifiedFetchDependency
  include Businesses::Concerns::BusinessAccess

  depends_on_clusters ApplicationRecord::Billing,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5

  layout false

  def show
    # this_entity.next_charge_amount works but next_charge_amount doesn't exist for Businesses, which this_entity can be
    if this_entity.is_a?(Organization)
      next_charge = this_organization.next_charge_amount
    elsif this_entity.is_a?(User)
      next_charge = this_user.next_charge_amount
    end

    render json: { nextChargeAmount: next_charge || nil }
  end
end
