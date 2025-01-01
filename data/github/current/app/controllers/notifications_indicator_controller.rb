# typed: true
# frozen_string_literal: true

# Small controller used only to fetch the status of the notifications icon
class NotificationsIndicatorController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  before_action :login_required

  def show
    render json: { mode: current_user.indicator_mode }
  end

  private

  # this is a safe pattern because of :login_required
  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
