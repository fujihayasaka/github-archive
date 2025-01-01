# typed: true
# frozen_string_literal: true

module Commits
  class BrowseRenameCommitsComponent < ApplicationComponent
    include GitHub::UTF8
    include ::TextHelper

    attr_reader :current_user, :current_repository, :last_commit, :new_file, :old_file, :has_rename_commits, :branch

    def initialize(current_user:, current_repository:, last_commit:, new_file:, old_file:, has_rename_commits:, branch:)
      @current_user = current_user
      @current_repository = current_repository
      @last_commit = last_commit
      @new_file = new_file
      @old_file = utf8(old_file)
      @has_rename_commits = has_rename_commits
      @branch = branch
    end

    def self.default
      Commits::BrowseRenameCommitsComponent.new(current_user: nil, current_repository: nil, last_commit: nil, new_file: nil,
        old_file: nil, has_rename_commits: false, branch: nil)
    end
  end
end
