# typed: true
# frozen_string_literal: true

class SamlController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:metadata]

  skip_before_action :first_run_check if GitHub.enterprise?
  before_action :enterprise_required

  # Service provider metadata for identity provider.
  def metadata # rubocop:todo GitHub/UseRestfulActions
    render xml: GitHub.auth.metadata
  end
end
