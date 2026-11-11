# typed: true
# frozen_string_literal: true

module Settings
  class CodespacesNavComponent < ApplicationComponent
    delegate_missing_to :@item

    def initialize(entity:, org_policy:, **system_arguments)
      @entity = entity
      @org_policy = org_policy
      @system_arguments = system_arguments
      @item = T.unsafe(Primer::Beta::NavList::Item).new(label: "Codespaces", **@system_arguments)
    end

    def settings_home_path
      settings_org_codespaces_path(@entity)
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

    def get_item_ids(section_name)
      subitem_highlights = settings_hash.dig(section_name, :sub_pages)

      if (item_id = settings_hash.dig(section_name, :item_id))
        subitem_highlights << item_id
      end

      subitem_highlights.append(get_path(section_name))
    end

    # Highlights control when the side navigation is visible. Sub-pages of a section should be highlighted
    # as well so the side navigation doesn't go away when navigating to them
    def all_highlights
      main_highlights = settings_hash.values.map { |section| section[:path] }
      sub_page_highlights = settings_hash.values.map { |section| section[:sub_pages] }
      (main_highlights.append(sub_page_highlights)).flatten
    end

    # Available sub-sections for organization level codespaces settings
    def settings_hash
      h = {
        "general" => {
          display_name: "General",
          item_id: :organization_codespaces_settings_general,
          path: settings_home_path,
          sub_pages: []
        },
      }
      h["policy"] = {
        display_name: "Policies",
        item_id: :settings_org_codespaces_policies,
        path: settings_org_codespaces_policies_path(@entity),
        sub_pages: [
          :settings_org_codespaces_policies_edit,
          :settings_org_codespaces_policies_new
        ]
      } unless @org_policy.must_upgrade_to_use_codespaces?
      h
    end
  end
end
