# typed: strict
# frozen_string_literal: true

module Discussions
  class OverviewDiscussionsComponent < ApplicationComponent
    MAX_DISCUSSIONS_TO_DISPLAY = 3

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(String) }
    attr_reader :view_all_discussions_path

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        repository: Repository,
        view_all_discussions_path: String,
        org_param: T.nilable(String),
      ).void
    end
    def initialize(repository:, view_all_discussions_path:, org_param: nil)
      @repository = repository
      @view_all_discussions_path = view_all_discussions_path
      @org_param = org_param
    end

    private

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    sig { returns(T::Enumerable[Discussion]) }
    memoize def top_discussions_this_month
      repository.discussions
      .created_since(1.month.ago)
      .most_upvotes_first
      .limit(MAX_DISCUSSIONS_TO_DISPLAY)
    end
  end
end
