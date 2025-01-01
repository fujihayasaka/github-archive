# typed: true
# frozen_string_literal: true

class Announcements::AnnouncementController < ApplicationController
  before_action :login_required

  delegate :target_for_conditional_access, to: :banner

  def dismiss # rubocop:todo GitHub/UseRestfulActions
    banner&.dismiss(current_user)

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def expand # rubocop:todo GitHub/UseRestfulActions
    banner&.expand(current_user)

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def resource_for_conditional_access  # rubocop:todo GitHub/UseRestfulActions
    banner
  end

  private

  def banner # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @banner ||= EnterpriseBanner.find(params[:id])
  end
end
