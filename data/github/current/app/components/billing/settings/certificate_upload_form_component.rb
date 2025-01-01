# typed: strict
# frozen_string_literal: true

class Billing::Settings::CertificateUploadFormComponent < ApplicationComponent
  extend T::Sig
  include UploadHelper

  class Styles < T::Struct
    const :header_tag, Symbol
    const :header_font_size, Integer
    const :text_mt, Integer
    const :text_size, Symbol
    const :button_size, String
  end

  sig { returns(Billing::Types::OrgOrBusiness) }
  attr_reader :account

  sig { returns(Symbol) }
  attr_reader :size

  sig { params(account: Billing::Types::OrgOrBusiness).void }
  def initialize(account:)
    @account = account
    @size = T.let(account.business? ? :large : :small, Symbol)
  end

  sig { returns(Styles) }
  memoize def styles
    if size == :small
      Styles.new(header_tag: :h4, header_font_size: 5, text_mt: 1, text_size: :small, button_size: "small")
    else
      Styles.new(header_tag: :h3, header_font_size: 3, text_mt: 2, text_size: :normal, button_size: "medium")
    end
  end

  sig { returns(String) }
  def allowed_extensions
    %w(.png .jpeg .pdf).join(",")
  end

  sig { returns(T::Boolean) }
  def exemption_form_exists?
    account.customer&.tax_exemption_status&.certificate_name.present?
  end

  sig { returns(String) }
  def github_sales_tax_docs_url
    "https://docs.github.com/billing/managing-your-github-billing-settings/adding-a-sales-tax-certificate"
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.billing_enabled? && account.present? && logged_in?

    account.business_entity?
  end

end
