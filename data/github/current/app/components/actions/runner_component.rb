# typed: true
# frozen_string_literal: true

module Actions
  class RunnerComponent < ApplicationComponent
    delegate :id, :name, :system_labels, :custom_labels, to: :runner
    delegate :os, :status, :custom_label_ids, to: :runner, private: true

    def initialize(
      runner:,
      owner_settings:,
      hidden: false,
      is_child_row: false,
      can_manage_runners: true,
      read_only: false,
      group_id: 0
    )
      @runner, @owner_settings, @hidden, @is_child_row, @can_manage_runners, @read_only, @group_id =
        runner, owner_settings, hidden, is_child_row, can_manage_runners, read_only, group_id
    end

    def icon_color_class
      case status
      when Actions::Runner::IDLE then :success
      when Actions::Runner::ACTIVE then :attention
      else :muted
      end
    end

    def can_manage_runners?
      @can_manage_runners && @owner_settings.can_manage_runners?
    end

    def delete_path
      @owner_settings.delete_runner_path(id: id, os: os)
    end

    def labels_path
      @owner_settings.labels_path(runner_id: id, selected_labels: custom_label_ids)
    end

    private

    attr_reader :runner
  end
end
