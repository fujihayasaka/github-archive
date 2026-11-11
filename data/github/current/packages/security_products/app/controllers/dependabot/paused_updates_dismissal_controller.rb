# typed: true
# frozen_string_literal: true

class Dependabot::PausedUpdatesDismissalController < ApplicationController
  before_action :login_required

  def create
    return head :not_found unless request.xhr?
    Dependabot::KV.store.set("user.dependabot_updates_paused_banner_hidden.#{current_user.id}", "true", expires: 90.days.from_now)

    head :ok
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
