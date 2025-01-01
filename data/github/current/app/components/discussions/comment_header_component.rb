# typed: true
# frozen_string_literal: true

module Discussions
  class CommentHeaderComponent < ApplicationComponent
    extend T::Sig
    include HydroHelper

    sig do
      params(
        discussion: Discussion,
        org_param: T.nilable(String),
        repository: Repository,
        sort: T.nilable(String)
      ).void
    end
    def initialize(discussion:, org_param:, repository:, sort:)
      @discussion = discussion
      @repository = repository
      @org_param = org_param
      @sort = sort
    end

    private

    attr_reader :discussion, :org_param, :repository, :sort

    memoize def comment_count
      discussion.comment_count
    end

    def hydro_discussions_comment_sort_tracking_data(discussion_id:, repository_id:, sort:)
      hydro_click_tracking_attributes("discussions.comment_sort_click",
        repository_id: repository_id,
        discussion_id: discussion_id,
        sort: sort,
      )
    end
  end
end
