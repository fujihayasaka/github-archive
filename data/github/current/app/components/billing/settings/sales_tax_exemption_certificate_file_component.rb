# typed: strict
# frozen_string_literal: true

class Billing::Settings::SalesTaxExemptionCertificateFileComponent < ApplicationComponent
  include UploadHelper
  include GitHub::Memoizer

  class Styles < T::Struct
    const :text_size, Symbol
    const :certificate_management_class, T.nilable(String)
  end

  sig { returns(Billing::TaxExemptionStatus) }
  attr_reader :tax_exemption_status

  sig { returns(Customer) }
  attr_reader :customer

  # size: :small or :large
  sig { params(tax_exemption_status: Billing::TaxExemptionStatus, size: Symbol).void }
  def initialize(tax_exemption_status:, size: :large)
    @tax_exemption_status = tax_exemption_status
    @customer = T.let(T.must(tax_exemption_status.customer), Customer)
    @size = T.let(size, Symbol)
  end

  sig { returns(Styles) }
  memoize def styles
    if @size == :small
      Styles.new(text_size: :small)
    else
      Styles.new(text_size: :normal, certificate_management_class: "d-flex flex-items-end")
    end
  end

  sig { returns(T.nilable(String)) }
  def exemption_form_file_name
    tax_exemption_status.display_certificate_filename
  end

  sig { returns(T.nilable(String)) }
  def exemption_form_file_path
    # TODO: Address issue here: https://github.com/github/github/pull/322136#discussion_r1589464709
    "#"
  end

  sig { returns(Billing::Types::OrgOrBusiness) }
  memoize def account
    return T.must(customer.business) if customer.business.present?

    customer.organizations.sole
  end
end
