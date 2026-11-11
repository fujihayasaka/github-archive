# typed: true
# frozen_string_literal: true

module Settings
  class CopilotNavComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    delegate_missing_to :@item

    rescue_from ActiveRecord::ActiveRecordError, with: :nothing

    def initialize(entity:, current_user:, **system_arguments)
      @entity = entity
      @current_user = current_user
      @system_arguments = system_arguments
      @item = T.unsafe(Primer::Beta::NavList::Item).new(label: "Copilot", **@system_arguments)
    end

    private

    def render?
      return true if user_enabled_to_assign_seats?
      return true if user_can_request_copilot_from_enterprise?
      return true if copilot_available?
      return true if copilot_organization.has_trial?
      return true if copilot_organization.is_available_for_copilot_signup?
      return true if copilot_organization.is_business_in_trial_period?

      false
    end

    # Available sub-sections for organization level copilot settings
    def sub_sections
      sections = []

      if org_has_copilot_access?
        sections << {
          display_name: "Access",
          item_id: :organization_copilot_settings_seat_management,
          path: settings_org_copilot_seat_management_path(@entity),
          sub_pages: []
        }

        sections << {
          display_name: "Policies",
          item_id: :organization_copilot_settings_policies,
          path: settings_org_copilot_policies_path(@entity),
          sub_pages: []
        }

        if code_review_approvals_enabled?
          sections << {
            display_name: "Code review",
            item_id: :organization_copilot_settings_code_review,
            path: settings_org_copilot_code_review_path(@entity),
            sub_pages: []
          }
        end

        sections << {
          display_name: "Models",
          item_id: :organization_copilot_settings_models,
          path: settings_org_copilot_models_path(@entity),
          sub_pages: []
        }

        if copilot_organization.can_use_org_copilot_custom_instructions?
          sections << {
            display_name: "Custom instructions",
            item_id: :organization_copilot_settings_custom_instructions,
            path: settings_org_copilot_custom_instructions_path(@entity),
            sub_pages: []
          }
        end

        if current_user&.feature_flag_enabled_or_raise?(:copilot_custom_models) || @entity.feature_flag_enabled_or_raise?(:copilot_custom_models) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          sections << {
            display_name: "Custom model",
            preview_label: true,
            item_id: :organization_copilot_settings_custom_models,
            path: settings_org_copilot_custom_models_path(@entity),
            sub_pages: []
          }
        end

        sections << {
          display_name: "Content exclusion",
          item_id: :org_settings_copilot_content_exclusion,
          path: org_settings_copilot_content_exclusion_path(@entity),
          sub_pages: []
        } if ::Copilot::ContentExclusion.is_available?(@entity)

      elsif user_enabled_to_assign_seats? || user_can_request_copilot_from_enterprise?

        sections << {
          display_name: "Access",
          item_id: :organization_copilot_settings_seat_management,
          path: settings_org_copilot_seat_management_path(@entity),
          sub_pages: []
        }

      elsif copilot_organization.is_available_for_copilot_signup? || copilot_organization.is_business_in_trial_period?

        sections << {
          display_name: "Access",
          item_id: :organization_copilot_settings_seat_management,
          path: settings_org_copilot_enable_path(@entity),
          sub_pages: []
        }

      end
      # This is an exception to the rule where copilot policies page does not get shown to the org admins if copilot is not enabled. https://github.com/github/Copilot-Controls/issues/570
      if show_policies_when_no_copilot?
        sections << {
          display_name: "Policies",
          item_id: :organization_copilot_settings_policies,
          path: settings_org_copilot_policies_path(@entity),
          sub_pages: []
        }
      end

      if show_models_when_no_copilot?
        sections << {
          display_name: "Models",
          item_id: :organization_copilot_settings_models,
          path: settings_org_copilot_models_path(@entity),
          sub_pages: []
        }
      end

      if coding_agent_tab_visible?
        sections << {
          display_name: ::Copilot::SWE_AGENT_DISPLAY_NAME_SHORT,
          item_id: :organization_copilot_settings_swe_agent,
          path: settings_org_copilot_swe_agent_path(@entity),
          sub_pages: [],
        }
      end

      if runner_type_tab_visible?
        sections << {
          display_name: "Runner type",
          item_id: :organization_copilot_settings_runner_type,
          path: settings_org_copilot_runner_type_path(@entity),
          sub_pages: [],
        }
      end

      sections
    end

    memoize def copilot_available?
      copilot_organization.has_copilot_for_business?
    end

    memoize def copilot_organization
      ::Copilot::Organization.new(@entity)
    end

    memoize def org_has_copilot_access?
      copilot_available? || copilot_organization.has_trial?
    end

    def code_review_approvals_enabled?
      code_review_approval_rollout_enabled? &&
        code_review_settings_available_for_org?
    end

    def code_review_approval_rollout_enabled?
      @entity.feature_flag_enabled?(:ccr_auto_approve_reviews, default: false) ||
        @entity.feature_flag_enabled?(:ccr_copilot_qualified_approvals, default: false)
    end

    def code_review_settings_available_for_org?
      !@entity.plan.legacy? && org_has_copilot_access?
    end

    def show_policies_when_no_copilot?
      !org_has_copilot_access? && copilot_organization.can_view_settings_page_with_copilot_disabled?
    end

    def show_models_when_no_copilot?
      # we show the models page if the org doesn't have copilot access but has direct org billing enabled,
      # direct org billing enables certain copilot features for the org even if they don't have a configured copilot plan
      # and we want to allow these orgs to select which models they want to use to support these features
      !org_has_copilot_access? && copilot_organization.has_copilot_direct_org_billing_enabled?
    end

    memoize def user_enabled_to_assign_seats?
      copilot_organization.can_enable_org_to_assign_seats?(@current_user)
    end

    memoize def user_can_request_copilot_from_enterprise?
      copilot_organization.can_request_copilot_from_enterprise?(@current_user)
    end

    memoize def kbs_disabled?
      FeatureFlag.vexi.enabled?(:kb_sunset, @current_user, default: false) && !FeatureFlag.vexi.enabled?(:kb_sunset_override, @current_user, default: false)
    end

    memoize def runner_type_standalone_enabled?
      FeatureFlag.vexi.enabled?(:ccr_runner_type_org_settings, @entity, default: false) &&
        FeatureFlag.vexi.enabled?(:copilot_swe_agent_runner_control_settings, @entity, default: false)
    end

    def coding_agent_tab_visible?
      !(GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, @entity, default: false))
    end

    def runner_type_tab_visible?
      runner_type_standalone_enabled? && (coding_agent_tab_visible? || copilot_code_review_enabled?)
    end

    def copilot_code_review_enabled?
      copilot_organization.code_review_enabled?
    end
  end
end
