# typed: true
# frozen_string_literal: true

module Settings
  class ActionsNavComponent < ApplicationComponent
    include Actions::LargerRunnersHelper
    delegate_missing_to :@item

    def initialize(entity:, **system_arguments)
      @entity = entity
      @system_arguments = system_arguments
      @item = T.unsafe(Primer::Beta::NavList::Item).new(
        label: "Actions",
        selected_item_id: @entity.is_a?(Organization) ? :organization_actions_settings : :repository_actions_settings,
        **@system_arguments
      )
    end

    def settings_home_path
      case @entity
      when ::Repository
        repository_actions_settings_path(user_id: @entity.owner, repository: @entity)
      when ::Organization
        settings_org_actions_path(@entity)
      end
    end

    def available_sections
      settings_hash.keys
    end

    def get_display_name(section_name)
      settings_hash.dig(section_name, :display_name)
    end

    def get_path(section_name)
      settings_hash.dig(section_name, :path)
    end

    def get_selected_by_item_ids(section_name)
      subitem_highlights = settings_hash.dig(section_name, :subitem_ids)
      subitem_highlights << settings_hash.dig(section_name, :item_id)

      subitem_highlights
    end

    def settings_hash
      case @entity
      when ::Repository
        repository_settings_hash
      when ::Organization
        organization_settings_hash
      end
    end

    # All currently supported sub-sections
    GENERAL = "general"
    RUNNERS = "runners"
    RUNNER_GROUPS = "runner-groups"
    CUSTOM_IMAGES = "custom-images"
    CACHES = "caches"

    # Available sub-sections for repository level action settings
    def repository_settings_hash
      settings_hash = {
        GENERAL => {
          display_name: "General",
          item_id: :repository_actions_settings_general,
          path: settings_home_path,
          subitem_ids: []
        },
        RUNNERS => {
          display_name: "Runners",
          item_id: :repository_actions_settings_runners,
          path: repository_actions_settings_runners_path(user_id: @entity.owner, repository: @entity),
          subitem_ids: [
            :repository_actions_settings_add_new_runner,
            :repository_actions_settings_runner_details
          ]
        }
      }

      settings_hash
    end

    # Available sub-sections for organization level action settings
    def organization_settings_hash
      settings_hash = {}
      adminable_by_current_user = @entity.adminable_by?(current_user)

      general_settings_entry = {
        display_name: "General",
        item_id: :organization_actions_settings,
        path: settings_home_path,
        subitem_ids: []
      }

      runners_entry = {
        display_name: "Runners",
        item_id: :organization_actions_settings_runners,
        path: settings_org_actions_runners_path(@entity),
        subitem_ids: [
          :organization_actions_settings_add_new_runner,
          :organization_actions_settings_runner_details,
          :organization_actions_settings_add_new_larger_runner,
          :organization_actions_settings_larger_runner_details,
          :organization_actions_settings_edit_larger_runner,
          :organization_actions_settings_runner_scale_set,
        ]
      }

      runner_groups_entry = {
        display_name: "Runner groups",
        item_id: :organization_actions_settings_runner_groups,
        path: settings_org_actions_runner_groups_path(@entity),
        subitem_ids: [
          :organization_actions_settings_runner_group
        ]
      }

      custom_images_entry = {
        display_name: "Custom images",
        item_id: :organization_actions_settings_custom_images,
        path: settings_org_actions_custom_images_path(@entity),
        subitem_ids: [
          :organization_actions_settings_custom_image
        ]
      }

      if adminable_by_current_user
        # The fine grained permissions also check for admin so this section can be removed alongside the FF
        settings_hash[GENERAL] = general_settings_entry
        settings_hash[RUNNERS] = runners_entry
        settings_hash[RUNNER_GROUPS] = runner_groups_entry
        settings_hash[CUSTOM_IMAGES] = custom_images_entry if is_custom_images_enabled?(entity: @entity)
      else
        has_runners_and_runner_groups_fgp = @entity.can_write_organization_runners_and_runner_groups?(current_user)
        settings_hash[GENERAL] = general_settings_entry if @entity.can_write_organization_actions_settings?(current_user) || has_runners_and_runner_groups_fgp
        settings_hash[RUNNERS] = runners_entry if has_runners_and_runner_groups_fgp
        settings_hash[RUNNER_GROUPS] = runner_groups_entry if has_runners_and_runner_groups_fgp
        settings_hash[CUSTOM_IMAGES] = custom_images_entry if has_runners_and_runner_groups_fgp && is_custom_images_enabled?(entity: @entity)
      end

      # Cache is not controlled by a fine-grained permission
      settings_hash[CACHES] = {
        display_name: "Caches",
        item_id: :organization_actions_settings_caches,
        path: settings_org_actions_caches_path(@entity),
        subitem_ids: []
      } if adminable_by_current_user

      settings_hash
    end
  end
end
