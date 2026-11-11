# typed: true
# frozen_string_literal: true

module Discussions
  class DuplicatePreventionComponent < ApplicationComponent
    MIN_DISCUSSION_COUNT = 10

    sig do
      params(
        user: T.untyped,
        repository: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(user:, repository:, org_param: nil)
      @user = user
      @repository = repository
      @org_param = org_param
    end

    # Public: Generate a search path that is used in creating the link to search for discussions
    def discussions_search_path
      agnostic_discussions_path(repository, org_param: org_param, discussions_q: "")
    end

    # Public: If the checkbox should show or the general notice to check for duplicates
    # This should show up if the user has no discussions in this repository yet
    def render_checkbox?
      !repository.discussions.where(user: user).exists?
    end

    private

    attr_reader :user, :repository

    sig { returns T.nilable(String) }
    attr_reader :org_param

    # The component should show if:
    #   * The repository is public
    #   * The repository has more than 10 discussions
    #   * The user does NOT have write access
    #   * This is the user's first discussion in the repo
    memoize def render?
      repository.public? && repository.discussions.count > MIN_DISCUSSION_COUNT && !repository.writable_by?(user)
    end
  end
end
