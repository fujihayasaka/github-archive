# typed: true
# frozen_string_literal: true

class Stafftools::CanaryController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :employee_only, only: [:update]

  def update
    if params[:toggle] == "true"
      cookies[:haproxy_backend] = "canary"
      cookies.delete(:staff_canary_opt_out)
    else
      cookies.delete(:haproxy_backend)
      cookies[:staff_canary_opt_out] = "true"
    end
    redirect_to :back
  end
end
