# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SpamController < Stafftools::Businesses::BusinessBaseController
  before_action :spamminess_check_required

  def create
    if params[:reason].blank?
      flash[:error] = "Please specify a reason for flagging this enterprise as spammy."
    else
      flag_business_spammy(this_business, reason: params[:reason], paid_confirm: params[:paid_confirm])
    end
    redirect_to :back
  end

  def destroy
    if allowlist?
      this_business.mark_as_hammy(actor: current_user, origin: :stafftools)
    else
      this_business.mark_not_spammy(actor: current_user, origin: :stafftools)
    end
    redirect_to :back
  end

  private

  def spamminess_check_required
    render_404 unless GitHub.spamminess_check_enabled?
  end

  def flag_business_spammy(business, reason: "Flagged by staff", paid_confirm: false)
    business.spammy_reason = nil
    reason += " #{GitHub::SpamChecker::HARD_SPAM_FLAG_PHRASE}" if paid_confirm
    business.mark_as_spammy(reason: reason, actor: current_user, origin: :stafftools)
  end

  def allowlist?
    params[:allowlist].present?
  end
end
