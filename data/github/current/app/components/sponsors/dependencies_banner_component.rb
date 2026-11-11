# typed: true
# frozen_string_literal: true

module Sponsors
  class DependenciesBannerComponent < ApplicationComponent
    include UsersHelper

    def initialize(sponsor_login:, total_dependencies: 0)
      @sponsor_login = sponsor_login
      @total_dependencies = total_dependencies.to_i
    end

    private

    def render?
      return false unless logged_in?
      return false unless GitHub.sponsors_enabled?
      return false if @sponsor_login.blank?
      return false if @total_dependencies <= 0

      current_user_can_admin_sponsor?
    end

    def current_user_can_admin_sponsor?
      return true if sponsor_is_current_user?
      current_user.potential_sponsor_logins.include?(@sponsor_login)
    end

    def message_subject
      if sponsor_is_current_user?
        "You rely"
      else
        "#{@sponsor_login} relies"
      end
    end

    def sponsor_is_current_user?
      @sponsor_login == current_user.login
    end
  end
end
