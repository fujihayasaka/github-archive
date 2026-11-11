# typed: true
# frozen_string_literal: true

class Stafftools::LabsController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def update
    if GitHub.employee_unicorn?
      GitHub::StaffOnlyCookie.delete!(cookies)
    elsif employee?
      set_employee_only_cookie(user: current_user, for_lab: true)
    end
    redirect_to :back
  end
end
