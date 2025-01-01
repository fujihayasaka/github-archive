# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckSuiteFilter < Platform::Inputs::Base
      description "The filters that are available when fetching check suites."

      argument :app_id, Int, "Filters the check suites created by this application ID.", required: false

      argument :check_name, String, "Filters the check suites by this name.", required: false
    end
  end
end
