# typed: true
# frozen_string_literal: true

class SiteShaController < ApplicationController
  before_action :disable_hydro_request_logging, only: [:index]

  # CAP not required, employee only and returns system configuration value
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :employee_only_unicorn, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  if GitHub.single_business_environment?
    skip_before_action :first_run_check, only: [:index]
  end

  def index
    render plain: GitHub.current_sha
  end

  private

  def stateless_request?
    action_name == "index" || super
  end
end
