# frozen_string_literal: true

module AdvisoryReviews
  module TwoStageApprovals
    class DialogsComponent < ApplicationComponent
      BOTH_STAGES_PENDING = :both_stages_pending
      STAGE_ONE_ALREADY_COMPLETE = :stage_one_already_complete
      STAGE_ONE_CONFIRMATION = :stage_one_confirmation
      PENDING_STAGE_ONE = :pending_stage_one
      STAGE_TWO_CONFIRMATION = :stage_two_confirmation

      renders_one :stage_two_confirmation_preamble
      renders_one :stage_two_confirmation_diff

      attr_reader :stage_one, :stage_two

      def initialize(approval_group:)
        @stage_one = approval_group.stage_one
        @stage_two = approval_group.stage_two
        @approval_group_guid = approval_group.guid
      end

      def show_dialog?(dialog)
        [stage_one.target_dialog, stage_two.target_dialog].include?(dialog)
      end

      def dialog_id(target_dialog)
        "#{test_selector(target_dialog)}-#{@approval_group_guid.downcase.strip.gsub(/[^a-z0-9-]+/, "-")}"
      end

      def test_selector(target_dialog)
        "dialog-#{target_dialog.to_s.downcase.strip.gsub(/[^a-z0-9-]+/, "-")}"
      end
    end
  end
end
