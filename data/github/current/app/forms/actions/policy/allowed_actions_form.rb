# typed: false
# frozen_string_literal: true

module Actions
  module Policy
    class AllowedActionsForm < ApplicationForm

      ALL_ACTIONS       = "all".freeze
      LOCAL_ACTIONS     = "local_only".freeze
      SPECIFIED_ACTIONS = "selected".freeze

      DISABLE_ACTIONS = Actions::PolicyUpdater::DISABLED

      VALID_OPTIONS = [ALL_ACTIONS, LOCAL_ACTIONS, SPECIFIED_ACTIONS].freeze

      form do |allowed_actions_form|
        allowed_actions_form.radio_button_group(name: "allowedactions", label: nil) do |actions_group|
          actions_group.radio_button(
            value: ALL_ACTIONS,
            label: all_actions_label,
            checked: all_actions_checked?,
            disabled: all_actions_disabled?,
            **(all_actions_disabled? ? { color: :muted } : {}),
            data: {
              action: "change:actions-policy-form#toggleSpecificOptions"
            }
          )

          if show_disable_actions_option?
            actions_group.radio_button(
              value: DISABLE_ACTIONS,
              label: "Disable actions",
              checked: @owner.actions_disabled?,
              caption: "The Actions tab is hidden and no workflows can run.",
              data: {
                action: "change:actions-policy-form#toggleSpecificOptions"
              }
            )
          end

          actions_group.radio_button(
            value: LOCAL_ACTIONS,
            label: local_actions_label,
            checked: local_actions_checked?,
            disabled: local_actions_disabled?,
            **(local_actions_disabled? ? { color: :muted } : {}),
            data: {
              action: "change:actions-policy-form#toggleSpecificOptions"
            }
          )

          actions_group.radio_button(
            value: SPECIFIED_ACTIONS,
            label: specified_actions_label,
            checked: specified_actions_checked?,
            disabled: specified_actions_disabled?,
            **(specified_actions_disabled? ? { color: :muted } : {}),
            data: {
              action: "change:actions-policy-form#toggleSpecificOptions",
              target: "actions-policy-form.selectRadio"
            },
            label_arguments: {
              aria: {
                live: "polite"
              }
            }
          ) do |specified_actions|
            specified_actions.nested_form(
              data: { target: "actions-policy-form.specificOptions" },
              hidden: !specified_actions_checked?,
              ml: 3, p: 3, border: 0, rounded: 2, color: :bg_subtle
            ) do |builder|
              Primer::Forms::FormList.new(
                Actions::Policy::SelectedActionsOptionsForm.new(
                  builder,
                  owner: @owner,
                  disabled: higher_level_specified_actions?
                ),

                Actions::Policy::AllowlistForm.new(
                  builder,
                  owner: @owner,
                  disabled: higher_level_specified_actions?,
                  include_workflows: include_reusable_workflow?
                )
              )
            end
          end
        end

        allowed_actions_form.check_box(
          name: "sha_pinning",
          value: "sha_pinning",
          label: "Require actions to be pinned to a full-length commit SHA",
          checked: sha_pinning_checked?,
          disabled: sha_pinning_disabled?,
          **(sha_pinning_disabled? ? { color: :muted } : {}),
        )

        allowed_actions_form.submit(
          name: :submit,
          label: "Save"
        )
      end

      def initialize(owner:, current_user: nil)
        @owner = owner
        @current_user = current_user
      end

      def render?
        return @owner.can_write_organization_actions_settings?(@current_user) if @owner.is_a?(Organization)
        true
      end

      def all_actions_checked?
        @owner.allows_all_actions?
      end

      def local_actions_checked?
        @owner.allows_local_actions_only?
      end

      def specified_actions_checked?
        @owner.allows_specified_actions?
      end

      def sha_pinning_checked?
        @owner.requires_sha_pinning?
      end

      def all_actions_disabled?
        available_options.exclude?(ALL_ACTIONS)
      end

      def local_actions_disabled?
        available_options.exclude?(LOCAL_ACTIONS)
      end

      def specified_actions_disabled?
        available_options.exclude?(SPECIFIED_ACTIONS)
      end

      def sha_pinning_disabled?
        @owner.owner_requires_sha_pinning? || disabled_at_any_level?
      end

      def all_actions_label
        "Allow all actions#{(include_reusable_workflow? ? " and reusable workflows" : "")}"
      end

      def local_actions_label
        if include_reusable_workflow?
          "Allow #{higher_level_entity_header} actions and reusable workflows"
        else
          "Allow local actions only"
        end
      end

      def specified_actions_label
        if include_reusable_workflow?
          "Allow #{higher_level_entity_header}, and select non-#{higher_level_entity_header}, actions and reusable workflows"
        else
          "Allow select actions"
        end
      end

      def local_actions_text
        if has_enterprise?
          "actions defined in a repository within the enterprise"
        elsif @owner.is_a?(Repository)
          "actions defined in a repository within #{@owner.owner.display_login}"
        else
          "actions defined in a repository within #{@owner.display_login}"
        end
      end

      def higher_level_entity_header
        higher_level_entity_with_options(
          enterprise_text: "enterprise",
          organization_text: "<login>",
          repository_text: "<login>"
        )
      end

      def higher_level_entity_text
        higher_level_entity_with_options(
          enterprise_text: "the enterprise",
          organization_text: "the <login> organization",
          repository_text: "<login>"
        )
      end

      def higher_level_entity_with_options(enterprise_text:, organization_text:, repository_text:)
        if has_enterprise?
          enterprise_text
        elsif @owner.is_a?(Repository)
          repository_text.sub("<login>", @owner.owner.display_login)
        else
          organization_text.sub("<login>", @owner.display_login)
        end
      end

      def show_disable_actions_option?
        @owner.is_a?(Repository)
      end

      def higher_level_specified_actions?
        return @_higher_level_specified_actions if defined?(@_higher_level_specified_actions)
        @_higher_level_specified_actions = @owner.highest_level_specified_actions?
      end

      def higher_level_entity
        return @_higher_level_entity if defined?(@_higher_level_entity)

        case @owner.highest_level_allowlist.entity
        when Business
          @_higher_level_entity = "enterprise"
        when Organization
          @_higher_level_entity = "organization"
        end
      end

      def specific_actions_docs_url
        "#{GitHub.help_url}/github/#{specific_actions_docs_entity_url}#allowing-select-actions-and-reusable-workflows-to-run"
      end

      private

      def has_enterprise?
        return @owner.owner.business.present? if @owner.is_a?(Repository)
        return @owner.business.present? if @owner.organization?
        true
      end

      def specific_actions_docs_entity_url
        if @owner.is_a?(Repository)
          "administering-a-repository/disabling-or-limiting-github-actions-for-a-repository"
        elsif @owner.organization?
          "setting-up-and-managing-organizations-and-teams/disabling-or-limiting-github-actions-for-your-organization"
        else
          "setting-up-and-managing-your-enterprise/enforcing-github-actions-policies-in-your-enterprise-account"
        end
      end

      def available_options
        return @_available_options if defined?(@_available_options)

        @_available_options = [DISABLE_ACTIONS] + VALID_OPTIONS

        if disabled_at_any_level?
          @_available_options = [DISABLE_ACTIONS]
        elsif @owner.owner_allows_local_actions_only?
          @_available_options = [DISABLE_ACTIONS, LOCAL_ACTIONS]
        elsif @owner.owner_allows_specified_actions_only?
          @_available_options = [DISABLE_ACTIONS, LOCAL_ACTIONS, SPECIFIED_ACTIONS]
        end

        @_available_options
      end

      # For an entity type, we always want to disable an option if the entity's
      # owner disabled Actions.
      #
      # Otherwise, we only want to disable the options if an a non-repository
      # (org or enterprise) disabled actions themselves.
      def disabled_at_any_level?
        return true if @owner.actions_disabled_by_owner?
        !@owner.is_a?(Repository) && @owner.actions_disabled?
      end

      # Helper function regarding https://github.com/github/c2c-actions/issues/3858
      def include_reusable_workflow?
        return @enabled if defined?(@enabled)

        # In GHES, calling reusable workflows across enterprise boundary is not possible
        #  due to the self hosted runner restriction
        @enabled = !GitHub.enterprise?
      end
    end
  end
end
