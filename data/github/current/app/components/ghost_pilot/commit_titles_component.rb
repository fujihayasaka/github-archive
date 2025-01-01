# typed: true
# frozen_string_literal: true

module GhostPilot
  class CommitTitlesComponent < BaseContextComponent
    erb_template <<-ERB
      <span hidden id="<%= element_id %>" data-allow-truncation data-description="Pull Request Commit Titles" data-value="<%= format_array_into_markdown_list(commit_messages) %>"></span>
    ERB

    def initialize(pull_request:)
      @pull_request = pull_request
    end

    def commit_messages
      @pull_request.comparison.commits.map(&:message)
    rescue => e
      Failbot.report(e)
      []
    end

    def element_id
      "pull-request-commit-titles"
    end
  end
end
