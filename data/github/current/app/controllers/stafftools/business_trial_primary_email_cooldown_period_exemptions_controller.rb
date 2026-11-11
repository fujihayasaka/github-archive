# typed: true
# frozen_string_literal: true

class Stafftools::BusinessTrialPrimaryEmailCooldownPeriodExemptionsController < StafftoolsController
  include Businesses::TrialAccountsHelper
  extend T::Helpers

  before_action :ensure_user_exists
  before_action :ensure_user_not_org
  before_action :dotcom_required

  def create
    set_exemption_from_primary_email_cooldown_period(this_user)

    flash[:notice] = "#{this_user} has been exempted from the primary email change cooldown period \
      of #{Businesses::TrialAccountsHelper::PRIMARY_EMAIL_COOLDOWN_PERIOD.inspect}."
    redirect_to :back
  end

  def destroy
    clear_exemption_from_primary_email_cooldown_period(this_user)

    flash[:notice] = "Primary email change cooldown period exemption cleared for #{this_user}."
    redirect_to :back
  end
end
