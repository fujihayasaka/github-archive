# typed: strict
# frozen_string_literal: true

module Discussions
  class RowActionsMenuComponent < ApplicationComponent
    sig { returns(Discussion) }
    attr_reader :discussion

    sig { returns(Repository) }
    attr_reader :repo

    sig { params(discussion: Discussion, repo: Repository).void }
    def initialize(discussion:, repo:)
      @discussion = discussion
      @repo       = repo
    end
  end
end
