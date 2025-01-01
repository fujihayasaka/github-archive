# typed: true
# frozen_string_literal: true

class Settings::PrimaryAvatarsController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required

  DESTROY_MESSAGE = "Your profile picture has been reset. " \
                    "It may take a few minutes to update across the site."

  def destroy
    current_user.primary_avatar&.destroy
    flash[:notice] = DESTROY_MESSAGE
    redirect_to settings_user_profile_path
  end
end
