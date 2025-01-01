# typed: true
# frozen_string_literal: true

class SleeptownController < ApplicationController
  # CAP not required, employee only and only times out
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :employee_only, only: [:index, :create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    duration = (params[:n] || 30).to_i
    sleep duration
    head :ok
  end

  # POST to this to hit custom request timeout.
  # See: lib/github/config.rb#request_method.
  # Formerly known as custom_sleeptown
  def create
    index
  end
end
