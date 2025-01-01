# typed: true
# frozen_string_literal: true

class Settings::Keys::CommitVerificationStatusesController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def update
    state = params["toggle_commit_verification_status"].to_s == "true" ? "enabled" : "disabled"
    current_user.set_commit_verification_status_state(actor: current_user, state: state)

    redirect_to settings_keys_path
  end

  private

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
