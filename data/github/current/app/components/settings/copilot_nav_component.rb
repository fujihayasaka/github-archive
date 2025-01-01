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

      copilot_organization.show_csv_exports?
    end

    # Available sub-sections for organization level copilot settings
    def sub_sections
      sections = []

      if copilot_available? || copilot_organization.has_trial?
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

        sections << {
          display_name: "Models",
          item_id: :organization_copilot_settings_models,
          path: settings_org_copilot_models_path(@entity),
          sub_pages: []
        }

        if (current_user&.feature_preview_enabled?(:copilot_chat_custom_instructions) || @entity.feature_preview_enabled?(:copilot_chat_custom_instructions)) && copilot_organization.can_use_org_copilot_custom_instructions?
          sections << {
            display_name: "Custom instructions",
            item_id: :organization_copilot_settings_custom_instructions,
            path: settings_org_copilot_custom_instructions_path(@entity),
            sub_pages: []
          }
        end

        if copilot_organization.can_use_copilot_enterprise_features?
          sections << {
            display_name: "Knowledge bases",
            item_id: :settings_org_copilot_chat_settings,
            path: settings_org_copilot_chat_settings_path(@entity),
            sub_pages: []
          }
        end

        if current_user&.feature_enabled?(:copilot_custom_models) || @entity.feature_enabled?(:copilot_custom_models)
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

      elsif copilot_organization.show_csv_exports?

        sections << {
          display_name: "CSV Exports",
          item_id: :organization_copilot_settings_csv_exports,
          path: settings_org_copilot_csv_exports_path(@entity),
          sub_pages: []
        }

      end

      sections << {
        display_name: ::Copilot::SWE_AGENT_DISPLAY_NAME_SHORT,
        item_id: :organization_copilot_settings_swe_agent,
        path: settings_org_copilot_swe_agent_path(@entity),
        sub_pages: [],
        preview_label: true
      }

      sections
    end

    memoize def copilot_available?
      copilot_organization.has_copilot_for_business?
    end

    memoize def copilot_organization
      ::Copilot::Organization.new(@entity)
    end

    memoize def user_enabled_to_assign_seats?
      copilot_organization.can_enable_org_to_assign_seats?(@current_user)
    end

    memoize def user_can_request_copilot_from_enterprise?
      copilot_organization.can_request_copilot_from_enterprise?(@current_user)
    end
  end
end
