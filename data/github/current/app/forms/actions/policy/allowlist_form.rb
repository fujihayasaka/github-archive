# typed: false
# frozen_string_literal: true

module Actions
  module Policy
    class AllowlistForm < ApplicationForm
      form do |allow_list_form|
        allow_list_form.text_area(
          name: "patterns",
          id: "allowlist",
          label: form_label,
          placeholder: "Enter a comma-separated list of #{policy_text}",
          style: "height:80px; min-height:80px; font-family: monospace;",
          disabled: @disabled,
          value: allowlist_content,
          data: {
            action: "focus:actions-policy-form#enableForm input:actions-policy-form#checkForWarnings",
            target: "actions-policy-form.allowlist",
          }
        )
      end

      def initialize(owner:, disabled: false, include_workflows: false)
        @owner = owner
        @disabled = disabled
        @include_workflows = include_workflows
      end

      def patterns
        return @_patterns if defined?(@_patterns)
        return @_patterns = @owner.highest_level_allowlist&.allowed_action_patterns if @disabled
        @_patterns = @owner.actions_allowlist&.allowed_action_patterns || []
      end

      def allowlist_content
        pattern_values = patterns.map(&:value).sort
        return "" unless pattern_values.any?

        pattern_values.join(",\r\n") + ",\r\n"
      end

      def policy_text
        return "actions and reusable workflows" if @include_workflows
        "actions"
      end

      def form_label
        "Allow or block specified #{policy_text}"
      end
    end
  end
end
