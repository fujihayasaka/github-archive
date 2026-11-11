# typed: true
# frozen_string_literal: true

module Issues
  class TrackedByHrefComponent < ApplicationComponent

    def initialize(owner:, repository:, issue_number:, issue_state: nil, issue_state_reason: nil, issue_title: nil, issue_url:, render_context: {}, tracked_by_title: nil)
      @reference_component = Issues::IssueReferenceComponent.new(
        owner: owner,
        repository: repository,
        issue_number: issue_number,
        render_context: render_context)
      @issue_title, @issue_state, @issue_state_reason, @issue_url, @owner, @repository = issue_title, issue_state, issue_state_reason, issue_url, owner, repository
      @render_context = render_context
      @tracked_by_title = tracked_by_title
    end

    private

    def render?
      @reference_component.render? && @issue_url.present?
    end

    def state
      @issue_state&.downcase&.to_sym
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

    def style_link_normal
      @render_context[:style_link_normal]
    end
  end
end
