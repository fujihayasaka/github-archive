# typed: strict
# frozen_string_literal: true

class Billing::SalesTaxExemptionsController < ApplicationController
  extend T::Sig
  before_action :ensure_billing_enabled, :login_required,
    :ensure_account_exists, :ensure_account_manageable_by_user, :ensure_business_entity

  sig { void }
  def create
    if account&.trade_screening_record&.validated_for_sales_tax?
      handler = Billing::Taxes::CertificateHandler.new(customer: customer)
      handler.submit_certificate(file: params[:file])
    else
      flash[:error] = "Your billing information is invalid. Please make corrections to your billing information and retry uploading the certificate."
    end

    redirect_to :back
  end

  sig { void }
  def destroy
    handler = Billing::Taxes::CertificateHandler.new(customer: customer)
    handler.reject_certificate(reason: "Customer requested removal of certificate")

    redirect_to :back
  end

  private

  sig { void }
  def ensure_business_entity
    redirect_to :back unless T.must(account).business_entity?
  end

  sig { void }
  def ensure_account_exists
    render_404 unless account
  end

  sig { returns(Customer) }
  memoize def customer
    T.must(T.must(account).customer)
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
  memoize def find_account_by_type
    if account_is_a_business?
      ::Business.find(params[:account_id])
    elsif account_is_an_org?
      ::Organization.find(params[:account_id])
    else
      current_user
    end
  end
  alias :account :find_account_by_type

  sig { returns(T.any(Billing::Types::Account, Symbol)) }
  def target_for_conditional_access
    find_account_by_type || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T::Boolean) }
  def account_is_a_business?
    params[:account_type] == "Business"
  end

  sig { returns(T::Boolean) }
  def account_is_an_org?
    params[:account_type] == "Organization"
  end

  sig { void }
  def ensure_account_manageable_by_user
    render_404 unless account_manageable_by_user?
  end

  sig { returns(T::Boolean) }
  def account_manageable_by_user?
    if account_is_a_business?
      business = T.cast(account, Business)
      business.owner?(current_user) || business.billing_manager?(current_user)
    elsif account_is_an_org?
      T.cast(account, Organization).billing_manageable_by?(current_user)
    else
      account == current_user
    end
  end
end
