# typed: true
# frozen_string_literal: true

class Billing::Notifications::DismissalsController < ApplicationController
  before_action :ensure_billing_enabled, :login_required,
    :ensure_account_exists, :ensure_account_manageable_by_user

  def create
    params[:product_tags].each do |product_tag|
      Billing::Notifications::Dismissal
        .new(account: account, actor_id: current_user.id)
        .create(params[:notice_key], product_tag: product_tag)
    end

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  def ensure_account_exists
    render_404 unless account
  end

  def target_for_conditional_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @account ||= find_account_by_type
  end
  alias :account :target_for_conditional_access

  def find_account_by_type
    if account_is_a_business?
      ::Business.find(params[:account_id])
    elsif account_is_an_org?
      ::Organization.find(params[:account_id])
    else
      current_user
    end
  end

  def account_is_a_business?
    params[:account_type] == "Business"
  end

  def account_is_an_org?
    params[:account_type] == "Organization"
  end

  def ensure_account_manageable_by_user
    render_404 unless account_manageable_by_user?
  end

  def account_manageable_by_user?
    if account_is_a_business?
      account.owner?(current_user) || account.billing_manager?(current_user)
    elsif account_is_an_org?
      account.billing_manageable_by?(current_user)
    else
      account == current_user
    end
  end
end
