# typed: true
# frozen_string_literal: true

class Businesses::TrialAccounts::InlineEmailVerificationComponent < ApplicationComponent
  include Businesses::TrialAccountsHelper

  sig { returns(Business) }
  attr_reader :business

  sig { returns(T.nilable(String)) }
  attr_reader :with_param

  sig { params(business: Business, with_param: T.nilable(String)).void }
  def initialize(business:, with_param: nil)
    @business = business
    @with_param = with_param
  end

  private

  sig { returns(String) }
  def verification_form_url
    if with_param.present?
      business_email_verification_path(business, with: with_param)
    else
      business_email_verification_path(business)
    end
  end
end
