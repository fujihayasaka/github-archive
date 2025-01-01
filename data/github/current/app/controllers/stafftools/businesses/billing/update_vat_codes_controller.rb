# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UpdateVatCodesController < Stafftools::Businesses::BusinessBaseController
  include Stafftools::Businesses::Billing::SharedControllerMethods

  sig { void }
  def update
    update_vat_codes_for_account
  end
end
