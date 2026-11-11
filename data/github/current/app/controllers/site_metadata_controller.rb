# typed: true
# frozen_string_literal: true

class SiteMetadataController < ApplicationController
  if GitHub.single_business_environment?
    skip_before_action :first_run_check
  end

  depends_on_clusters ApplicationRecord::Mysql1

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :employee_only_unicorn, only: [:index]

  def index
    render json: {
      api_url: GitHub.api_url,
    }
  end
end
