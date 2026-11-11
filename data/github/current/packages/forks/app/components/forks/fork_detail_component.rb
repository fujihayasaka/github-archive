# typed: true
# frozen_string_literal: true

class Forks::ForkDetailComponent < ApplicationComponent
  attr_reader :fork, :attributes
  delegate :avatar_for, :social_count, to: :helpers

  AVATAR_SIZE = 16.freeze

  sig { params(fork: Repository, attributes: T::Hash[Symbol, T.untyped]).void }
  def initialize(fork, attributes)
    @fork = fork
    @attributes = attributes
  end

  private

  def details
    fork_last_updated = @attributes[:last_updated][@fork.id]
    if fork_last_updated && fork_last_updated > @fork.created_at
      updated_at_component = Forks::DetailTimeComponent.new("Updated", fork_last_updated)
    else
      updated_at_component = Primer::Beta::Text.new(font_size: :small, test_selector: "fork-detail-updated")
        .with_content("Never updated")
    end

    [
      Forks::DetailCounterComponent.new(
        detail_count(:stargazer_counts),
        "stargazers-count",
        "star",
        stargazers_repository_path(repository: @fork, user_id: @fork.owner)
      ),
      Forks::DetailCounterComponent.new(
        detail_count(:child_fork_counts),
        "forks-count",
        "repo-forked",
        forks_path(repository: @fork, user_id: @fork.owner)
      ),
      Forks::DetailCounterComponent.new(
        detail_count(:open_issue_counts),
        "open-issues-count",
        "issue-opened",
        repository_issues_path({ state: "open" }, @fork)
      ),
      Forks::DetailCounterComponent.new(
        detail_count(:open_pull_request_counts),
        "open-pull-requests-count",
        "git-pull-request",
        repository_pull_requests_path({ state: "open" }, @fork)
      ),
      Forks::DetailTimeComponent.new("Created", @fork.created_at&.to_time),
      updated_at_component,
    ].freeze
  end

  def fork_url
    repository_path(@fork)
  end

  def owner_avatar
    avatar_for(fork.owner, AVATAR_SIZE, class: "v-align-text-bottom")
  end

  def detail_count(detail_id)
    social_count(attributes[detail_id][@fork.id])
  end
end
