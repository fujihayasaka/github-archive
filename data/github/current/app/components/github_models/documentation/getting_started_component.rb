# typed: true
# frozen_string_literal: true

class GitHubModels::Documentation::GettingStartedComponent < ApplicationComponent
  def initialize(sdk:, language:, task:, code_sample:, is_billing_enabled:)
    @sdk = sdk
    @language = language
    @task = task
    @code_sample = code_sample
    @is_billing_enabled = is_billing_enabled
  end
end
