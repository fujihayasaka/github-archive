# typed: true
# frozen_string_literal: true

module Repository::CommitCommentsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  # Public: Are commit comments enabled for this repository?
  sig { returns T::Boolean }
  def commit_comments_enabled?
    T.bind(self, Repository)
    CommitCommentsConfig.new(self).commit_comments_enabled?
  end
end
