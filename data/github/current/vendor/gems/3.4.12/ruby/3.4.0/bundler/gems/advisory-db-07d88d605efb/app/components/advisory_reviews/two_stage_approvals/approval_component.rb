# frozen_string_literal: true

module AdvisoryReviews
  module TwoStageApprovals
    class ApprovalComponent < ApplicationComponent
      attr_reader :stage_one, :stage_two, :system_arguments

      renders_one :stage_two_confirmation_preamble
      renders_one :stage_two_confirmation_diff

      def initialize(stage_one:, stage_two:, stage_locked_icon: :lock, stage_completed_icon: :"check-circle-fill", **system_arguments)
        @stage_one = context_aware_stage(stage_one, :stage_one)
        @stage_two = context_aware_stage(stage_two, :stage_two)
        @stage_locked_icon = stage_locked_icon
        @stage_completed_icon = stage_completed_icon
        @system_arguments = system_arguments
      end

      def dialogs
        @dialogs ||= DialogsComponent.new(approval_group: self)
      end

      def guid
        @guid ||= SecureRandom.uuid
      end

      def target_dialog(stage)
        case stage
        when :stage_one
          stage_one_target_dialog
        when :stage_two
          stage_two_target_dialog
        end
      end

      def target_dialog_id(stage)
        dialogs.dialog_id(target_dialog(stage))
      end

      def icon(stage)
        case stage
        when :stage_one
          stage_one_icon
        when :stage_two
          stage_two_icon
        end
      end

      def button_attributes(stage)
        # Attributes common to both buttons
        common_button_attributes
          .merge case stage
                 when :stage_one
                   # Attributes specific to the stage
                   stage_one.attributes
                     # Attributes specific to the positioning of stage one within the group
                     .merge(stage_one_position_attributes)
                 when :stage_two
                   # Attributes specific to the stage
                   stage_two.attributes
                     # Attributes specific to the positioning of stage two within the group
                     .merge(stage_two_position_attributes)
                 end
      end

      private

      # Set the context for each stage so it can be used to determine current state
      def context_aware_stage(stage, stage_slug)
        stage.set_approval_context!(stage_slug, self)
        stage
      end

      def stage_one_target_dialog
        if stage_one.disabled? && stage_two.disabled?
          dialogs.class::BOTH_STAGES_PENDING
        elsif stage_one.disabled? && !stage_two.disabled?
          dialogs.class::STAGE_ONE_ALREADY_COMPLETE
        else
          dialogs.class::STAGE_ONE_CONFIRMATION
        end
      end

      def stage_two_target_dialog
        if stage_one.disabled? && stage_two.disabled?
          dialogs.class::BOTH_STAGES_PENDING
        elsif !stage_one.disabled? && stage_two.disabled?
          dialogs.class::PENDING_STAGE_ONE
        else
          dialogs.class::STAGE_TWO_CONFIRMATION
        end
      end

      def stage_one_icon
        if stage_one.disabled? && stage_two.disabled?
          @stage_locked_icon
        elsif stage_one.disabled? && !stage_two.disabled?
          @stage_completed_icon
        else
          stage_one.active_icon
        end
      end

      def stage_two_icon
        if (stage_one.disabled? && stage_two.disabled?) || (!stage_one.disabled? && stage_two.disabled?)
          @stage_locked_icon
        else
          stage_two.active_icon
        end
      end

      def stage_one_position_attributes
        { mb: 0, classes: "rounded-bottom-0 btn-large" }
      end

      def stage_two_position_attributes
        { mt: 0, mb: 2, border_top: 0, classes: "rounded-top-0 btn-large" }
      end

      def common_button_attributes
        { w: :full, display: :flex, justify_content: :flex_start, align_items: :center }
      end
    end
  end
end
