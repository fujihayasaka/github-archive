# typed: true
# frozen_string_literal: true

module Repos::Security
  class SecurityShowPageComponent < ApplicationComponent
    attr_reader :alert_title, :alert_number

    # Discussions are ongoing about what to do with alert numbers
    # See https://github.com/github/security-products/issues/187
    def initialize(alert_title:, alert_number: nil)
      @alert_title = alert_title
      @alert_number = alert_number
    end

    # Content to render above the heading, like page-level banners
    renders_one :pre_header

    # Action buttons for the alert
    renders_one :alert_actions

    # Information about the status of the alert
    renders_one :status_information, -> (state:, title: nil, &block) do
      T.bind(self, SecurityShowPageComponent)
      properties = get_state_component_properties_from_state(state)
      title ||= properties[:title]

      content_tag :div, { class: "mb-2" } do
        state_html_string = content_tag :span, { class: "mr-1 d-inline-block" } do
          render Primer::Beta::State.new(title: title, scheme: properties[:scheme], tag: :span, test_selector: "alert-state") do
            render(Primer::Beta::Octicon.new(icon: properties[:icon])) + " #{properties[:label]}"
          end
        end
        state_html_string + block.call
      end
    end

    # Main content
    renders_one :main

    # Alert severity, shown in the sidebar
    renders_one :severity, types: {
      code_scanning: CodeScanning::AlertSeverityComponent,
      dependabot: DependabotAlerts::SeverityDetailsComponent,
      dependabot_next: DependabotAlerts::SeverityDetailsNextComponent
    }

    # Assignees section, shown in the sidebar
    renders_one :assignees, Repos::Security::AssigneesSectionComponent

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

    renders_one :affected_branches

    # Development section, shown in the sidebar
    renders_one :development_section, Repos::Security::DevelopmentSectionComponent

    renders_one :security_campaigns

    # Generic sidebar sections
    renders_many :sidebar_sections, -> (title: nil, test_selector: nil, &block) do
      T.bind(self, SecurityShowPageComponent)
      if title.present?
        title_tag = content_tag :h3, { class: "h6 color-fg-muted mb-2" } do
          title
        end
      end
      content_tag :div, (title.present? ? title_tag + block.call : block.call), (test_selector_data_hash(test_selector) if test_selector.present?)
    end

    # CWE (Common Weakness Enumeration) details, shown in the sidebar
    renders_one :cwe_section, Repos::Security::CWESectionComponent

    private

    def get_state_component_properties_from_state(state)
      default_properties = { scheme: :default, icon: "shield" }
      case state.to_sym
      when :in_pr
        default_properties.merge({
          title: "In pull request",
          label: "In pull request"
        })
      when :in_branch
        default_properties.merge({
          title: "In branch",
          label: "In branch"
        })
      when :unknown
        default_properties.merge({
          title: "Not in default branch",
          label: "Not in default branch"
        })
      when :dismissed
        default_properties.merge({
          title: "Status: Dismissed",
          label: "Dismissed",
          scheme: :closed,
          icon: "shield-slash"
        })
      when :auto_dismissed
        default_properties.merge({
          title: "Status: Auto-dismissed",
          label: "Dismissed",
          scheme: :closed,
          icon: "shield-slash"
        })
      when :fixed
        default_properties.merge({
          title: "Status: Fixed",
          label: "Fixed",
          scheme: :merged,
          icon: "shield-check"
        })
      when :open
        default_properties.merge({
          title: "Status: Open",
          label: "Open",
          scheme: :open
        })
      when :withdrawn
        default_properties.merge({
          title: "Status: Withdrawn",
          label: "Withdrawn",
          scheme: :default,
          icon: "shield-lock"
        })
      end
    end
  end
end
