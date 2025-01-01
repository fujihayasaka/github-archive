# typed: true
# frozen_string_literal: true

class Stafftools::AutoPayController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_billing_enabled
  before_action :ensure_billing_record_exists

  def enable # rubocop:todo GitHub/UseRestfulActions
    this_user.enable_auto_pay! params[:auto_pay_reason].to_sym, actor: current_user
    redirect_to billing_stafftools_user_path(this_user)
  end

  def disable # rubocop:todo GitHub/UseRestfulActions
    this_user.disable_auto_pay! params[:auto_pay_reason].to_sym, actor: current_user
    redirect_to billing_stafftools_user_path(this_user)
  end

  private

  def ensure_billing_record_exists
    unless this_user.has_billing_record?
      flash[:error] = "There's no payment record to update."
      redirect_to :back
    end
  end
end
