# typed: true
# frozen_string_literal: true

class AccountVerifications::ResendController < ApplicationController
  before_action :ensure_email_verification_required

  def create
    flash[:notice] = "We sent a verification email to #{@email}. Please follow the instructions in it."
    accountless_email_verification.reset_verification_token_and_sent_email

    redirect_to_return_to(fallback: account_verifications_path)
  end

  private

  # CAP not required, this is a signed out page
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def accountless_email_verification
    verification_id = session[:accountless_email_verification_id].presence || params[:verification].presence
    @accountless_email_verification = User::AccountlessEmailVerification.find_email_verification(verification_id)
  end

  def ensure_email_verification_required
    redirect_to home_path unless accountless_email_verification
  end
end
