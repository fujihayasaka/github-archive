# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class SettingsEnvironmentsListComponent < ApplicationComponent
      def initialize(repo:, environments:, secret_counts:, variable_counts:)
        @repo = repo
        @environments = environments
        @secret_counts = secret_counts
        @variable_counts = variable_counts
      end
    end
  end
end
