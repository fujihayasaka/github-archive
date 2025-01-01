# typed: false
# frozen_string_literal: true

module Actions
  module Policy
    class AllowlistForm < ApplicationForm
      form do |allow_list_form|
        if show_allowlist?
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
      end

      def initialize(owner:, disabled: false, include_workflows: false)
        @owner = owner
        @disabled = disabled
        @include_workflows = include_workflows
        @blocklist_enabled = if @disabled
          @owner.highest_level_allowlist&.entity.feature_enabled?(:actions_blocklist)
        else
          @owner.feature_enabled?(:actions_blocklist)
        end
      end

      def patterns
        return @_patterns if defined?(@_patterns)
        return @_patterns = @owner.highest_level_allowlist&.allowed_action_patterns if @disabled
        @_patterns = @owner.actions_allowlist&.allowed_action_patterns || []
      end

      def show_allowlist?
        !@owner.is_a?(Repository) || @owner.can_use_actions_allowlist?
      end

      def show_allowlist_private_repo_warning?
        @owner.is_a?(Organization) && !@owner.can_use_actions_allowlist?
      end

      def billing_path
        return "#" unless @owner.organization?
        @view_context.settings_org_billing_path(@owner)
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
        return "Allow or block specified #{policy_text}" if @blocklist_enabled
        "Allow specified #{policy_text}"
      end
    end
  end
end
