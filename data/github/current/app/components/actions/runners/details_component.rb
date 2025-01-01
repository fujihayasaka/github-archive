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
        if user_or_global_feature_enabled?(:actions_runners_use_runner_admin_service)
          @owner_settings.labels_path(runner_id: @runner.id, selected_labels: @runner.labels.map(&:name))
        else
          @owner_settings.labels_path(runner_id: @runner.id, selected_labels: @runner.labels.map(&:id))
        end
      end
    end
  end
end
