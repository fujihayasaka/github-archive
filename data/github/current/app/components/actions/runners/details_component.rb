# typed: true
# frozen_string_literal: true

module Actions
  module Runners
    class DetailsComponent < ApplicationComponent
      def initialize(runner:, check_run:, runner_group:, owner_settings:)
        @runner = runner
        @check_run = check_run
        @runner_group = runner_group
        @owner_settings = owner_settings
      end

      def labels_path
        @owner_settings.labels_path(
          runner_id: @runner.id,
          selected_labels: @runner.labels.map { |l| l.respond_to?(:id) ? l.id : l.name }
        )
      end
    end
  end
end
