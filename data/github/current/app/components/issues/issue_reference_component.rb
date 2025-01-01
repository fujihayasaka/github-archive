# typed: true
# frozen_string_literal: true

module Issues
  class IssueReferenceComponent < ApplicationComponent
    include ViewComponent::InlineTemplate

    erb_template <<~ERB
      <span><%= reference_label %></span>
    ERB

    def initialize(owner:, repository:, issue_number:, render_context: {})
      @owner, @repository, @issue_number = owner, repository, issue_number
      @render_context = render_context
    end

    def render?
      @owner.present? && @repository.present? && @issue_number.present?
    end

    private

    def reference_label
      current_owner = @render_context[:current_owner]
      current_repository = @render_context[:current_repository]
      label = ""
      if current_owner.present? && current_owner != @owner
        label = "#{@owner}/#{@repository}"
      elsif current_repository.present? && current_repository != @repository
        label = "#{@repository}"
      end
      label += "##{@issue_number}"
    end
  end
end
