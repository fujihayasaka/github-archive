# frozen_string_literal: true

module AdvisoryReviews
  module TwoStageApprovals
    # Manages a single stage of a two-stage approval process for an advisory review
    class Stage
      class MissingContextError < StandardError; end

      attr_reader :label, :active_icon, :disabled, :action, :past_tense_action, :scheme, :confirmation_url, :confirmation_params, :test_selector
      alias disabled? disabled

      def initialize(label:, icon:, action:, past_tense_action:, confirmation_url:, disabled: true, scheme: :primary, confirmation_params: {}, test_selector: nil)
        @label = label
        @active_icon = icon
        @disabled = disabled
        @action = action
        @past_tense_action = past_tense_action
        @confirmation_url = confirmation_url
        @confirmation_params = confirmation_params
        @scheme = scheme
        @test_selector = test_selector
      end

      def attributes
        {
          aria: {
            disabled: disabled?,
            haspopup: true,
          },
          data: {
            "show-dialog-id": target_dialog_id,
            targets: disabled? ? nil : "form-tracker.disableWhenChanged",
          },
          inactive: disabled?,
          scheme: scheme,
          test_selector: test_selector,
        }
      end

      def set_approval_context!(stage_slug, parent_two_stage_approval)
        @approval_context = parent_two_stage_approval
        @approval_context_slug = stage_slug
      end

      def target_dialog
        with_approval_context :target_dialog
      end

      def target_dialog_id
        with_approval_context :target_dialog_id
      end

      def icon
        with_approval_context :icon
      end

      def button_attributes
        with_approval_context :button_attributes
      end

      private

      def with_approval_context(context_method)
        unless defined?(@approval_context) && defined?(@approval_context_slug)
          raise MissingContextError, "No context set for this stage"
        end

        @approval_context.public_send(context_method, @approval_context_slug)
      end
    end
  end
end
