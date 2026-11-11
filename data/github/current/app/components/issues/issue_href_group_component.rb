# typed: true
# frozen_string_literal: true

module Issues
  class IssueHrefGroupComponent < ApplicationComponent

    def initialize(issue_href_components:)
      @issue_href_components = issue_href_components
    end

    private

    def render?
      @issue_href_components.present? && @issue_href_components.any?
    end

    def href_components
      @issue_href_components
    end
  end
end
