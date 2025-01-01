# typed: true
# frozen_string_literal: true

module Issues
  class IssueHrefComponent < ApplicationComponent
    include HydroHelper

    def initialize(owner:, repository:, is_pull_request: false, issue_number:, issue_state: nil, issue_state_reason: nil, issue_title: nil, issue_url:, item_type: nil, render_context: {})
      @reference_component = Issues::IssueReferenceComponent.new(
        owner: owner,
        repository: repository,
        issue_number: issue_number,
        render_context: render_context)
      @is_pull_request, @issue_title, @issue_state, @issue_state_reason, @issue_url, @item_type, @owner, @repository = is_pull_request, issue_title, issue_state, issue_state_reason, issue_url, item_type, owner, repository
      @render_context = render_context
    end

    private

    def render?
      @reference_component.render? && @issue_url.present?
    end

    def state
      @issue_state&.downcase&.to_sym
    end

    def is_pull_request?
      @is_pull_request
    end

    def state_reason
      @issue_state_reason&.downcase&.to_sym
    end

    def title
      return @issue_title unless @issue_title.present?
      GitHub::Goomba::TitleMarkdownFilter.call(@issue_title)
    end

    def url
      @issue_url
    end

    def reference_component
      @reference_component
    end

    def hovercard_attributes
      @render_context[:hovercard_attributes]
    end

    def should_truncate?
      @render_context[:truncate].present? && @render_context[:truncate]
    end

    def send_click_hydro_event?
      @render_context[:issue_click_hydro_event].present?
    end

    def issue_click_hydro_event
      @render_context[:issue_click_hydro_event]
    end

    def style_link_normal
      @render_context[:style_link_normal]
    end

    def octicon_type
      if is_pull_request?
        return "git-pull-request-draft" if state == :draft
        return "git-pull-request"
      end
      state == :open ? "issue-opened" : "issue-closed"
    end
  end
end
