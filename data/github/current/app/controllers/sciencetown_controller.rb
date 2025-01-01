# typed: true
# frozen_string_literal: true

class SciencetownController < ApplicationController
  before_action :employee_only, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  # cap_bypass internal only endpoint
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  # For science testing. Include a fail= parameter for customization.
  def index
    case params["fail"]
    when "internal" # internal errors
      science "sciencetown" do |e|
        e.context user: current_user.login # rubocop:disable GitHub/DoNotAllowLogin login is ok in science experiments
        e.use { true }
        e.try { true }
        e.clean { raise "kaboom" }
      end
    when "exception" # raising different internal exceptions
      science "sciencetown" do |e|
        e.context user: current_user.login # rubocop:disable GitHub/DoNotAllowLogin login is ok in science experiments
        e.use { raise "control" }
        e.try { raise "candidate" }
      end
    else # nothing goes wrong!
      science "sciencetown" do |e|
        e.context user: current_user.login # rubocop:disable GitHub/DoNotAllowLogin login is ok in science experiments
        e.use { true }
        e.try { true }
      end
    end

    render plain: "Sciencetown! Find the results in the `sciencetown` experiment."
  rescue => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e)
    render plain: "Sciencetown! An error has occurred, check sentry and/or splunk for more details. Request_ID = #{request_id}"
  end
end
