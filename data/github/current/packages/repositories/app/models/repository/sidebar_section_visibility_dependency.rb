# typed: true
# frozen_string_literal: true

module Repository::SidebarSectionVisibilityDependency
  extend T::Helpers

  requires_ancestor { Repository }

  SIDEBAR_SECTIONS = %w[packages releases environments deployments pages_url].freeze

  # Internal: Stores the sidebar section visibility settings
  # Expects a hash of section names that have a value of "1" for visible and "0" for hidden.
  # eg. update_sidebar_section_visibility({"releases"=>"1", "packages"=>"1", "environments"=>"0"})
  #
  # returns nil
  def update_sidebar_section_visibility(sections, actor:)
    old_settings = sidebar_sections_visibility

    if sections.present?
      SIDEBAR_SECTIONS.each do |section|
        public_send("disable_#{section}_sidebar_section", actor) if sections[section] == "0"
        public_send("enable_#{section}_sidebar_section", actor) if sections[section] == "1" || sections[section].nil?
      end
    end

    # Keep stats on sections that are hidden so we can determine
    # from a product standpoint what sections need work.
    sections.each do |name, value|
      # If old value was "1" or there was no old value (nil)
      if value == "0" && (old_settings[name].nil? || old_settings[name] == "1")
        GitHub.dogstats.increment("edit_repositories.hidden_sidebar_sections.count", sample_rate: 1, tags: ["section:#{name}"])
      elsif value == "1" && old_settings[name] == "0"
        GitHub.dogstats.decrement("edit_repositories.hidden_sidebar_sections.count", sample_rate: 1, tags: ["section:#{name}"])
      end
    end
  end

  def sidebar_sections_visibility
    data_from_configuration_entries = {}
    SIDEBAR_SECTIONS.each do |section|
      data_from_configuration_entries[section] = public_send("#{section}_sidebar_section_enabled?") ? "1" : "0"
    end

    data_from_configuration_entries
  end

  # Internal: Check if a single section is visible
  #
  # returns Boolean
  def sidebar_section_enabled?(section)
    visibility = sidebar_sections_visibility

    visibility[section.to_s].nil? || visibility[section.to_s] == "1"
  end
end
