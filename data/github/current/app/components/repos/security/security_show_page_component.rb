# typed: true
# frozen_string_literal: true

module Repos::Security
  class SecurityShowPageComponent < ApplicationComponent
    def initialize; end

    def before_render
      raise ArgumentError, "react_header slot is required" unless react_header?
    end

    # Content to render above the heading, like page-level banners
    renders_one :pre_header

    # React header content
    renders_one :react_header

    # Action buttons for the alert
    renders_one :alert_actions

    # Main content
    renders_one :main

    # React sidebar content
    renders_one :react_sidebar

    # Alert severity, shown in the sidebar
    renders_one :severity, types: {
      dependabot: DependabotAlerts::SeverityDetailsComponent,
      dependabot_next: DependabotAlerts::SeverityDetailsNextComponent
    }

    # Assignees section, shown in the sidebar
    renders_one :assignees, types: {
      picker: Repos::Security::AssigneesSectionComponent,
      ghas_upsell: Repos::Security::AssigneesGhasUpsellComponent,
    }

    renders_one :epss_score, GlobalAdvisories::EPSSComponent

    # Tags, shown in the sidebar
    renders_many :tags, -> (title:, href: nil) do
      T.bind(self, SecurityShowPageComponent)
      render(Primer::Beta::Label.new(
        tag: href.present? ? :a : :span,
        href: href,
        title: title,
        scheme: :secondary,
        test_selector: "alert-tag",
        mb: 1)) { title }
    end

    # Runtime risks, shown in the sidebar
    renders_one :runtime_risks, Repos::Security::RuntimeRisksComponent

    SIDEBAR_SECTION_RENDERER = -> (title: nil, test_selector: nil, &block) do
      T.bind(self, SecurityShowPageComponent)
      if title.present?
        title_tag = content_tag :h3, { class: "h6 color-fg-muted mb-2" } do
          title
        end
      end
      content_tag :div, (title.present? ? title_tag + block.call : block.call), (test_selector_data_hash(test_selector) if test_selector.present?)
    end

    # Generic sidebar sections
    renders_many :sidebar_sections, SIDEBAR_SECTION_RENDERER
    renders_many :pre_cwe_sidebar_sections, SIDEBAR_SECTION_RENDERER

    # CWE (Common Weakness Enumeration) details, shown in the sidebar
    renders_one :cwe_section, Repos::Security::CWESectionComponent
  end
end
