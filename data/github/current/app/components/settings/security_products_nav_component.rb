# typed: true
# frozen_string_literal: true

module Settings
  class SecurityProductsNavComponent < ApplicationComponent
    delegate_missing_to :@item

    # All currently supported sub-sections
    CONFIGURATIONS = "configurations"
    GLOBAL_SETTINGS = "settings"

    def initialize(entity:, **system_arguments)
      @entity = entity
      @system_arguments = system_arguments
      @item = T.unsafe(Primer::Beta::NavList::Item).new(label: "Code security", **@system_arguments)
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

    # Returns and array containing the sub-page symbols and the path for the given section
    def get_item_ids(section_name)
      subitem_highlights = settings_hash.dig(section_name, :sub_pages)
      if (item_id = settings_hash.dig(section_name, :item_id))
        subitem_highlights << item_id
      end
      subitem_highlights.append(get_path(section_name))
    end

    # Available sub-sections for organization level Code Security settings
    def settings_hash
      menu_hash = {
        CONFIGURATIONS => {
          display_name: "Configurations",
          item_id: :security_products,
          path: settings_org_security_products_path(@entity),
          sub_pages: [
            :settings_org_security_products,
            :settings_org_security_configurations_new,
            :settings_org_security_configurations_edit
          ]
        },
        GLOBAL_SETTINGS => {
          display_name: "Global settings",
          item_id: :security_analysis,
          path: settings_org_security_analysis_path(@entity),
          sub_pages: [
            :settings_org_dependabot_rules,
            :settings_org_new_dependabot_rule,
            :settings_org_edit_dependabot_rule,
            :settings_org_edit_global_dependabot_rule
          ]
        }
      }

      menu_hash
    end
  end
end
