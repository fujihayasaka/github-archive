# typed: true
# frozen_string_literal: true

module PullRequests
  class BranchNameComponent < ApplicationComponent

    attr_reader :repo_name, :repo_owner, :branch, :prepend_login, :suffix, :truncate_branch_only

    def initialize(repository:, branch:, prepend_login: false, suffix: "", truncate_branch_only: false)
      @repo_name = repository&.name.try { |s| s.force_encoding("utf-8").scrub! }
      @repo_owner = repository&.owner_display_login.try { |s| s.force_encoding("utf-8").scrub! }
      @branch = branch.try { |s| s.dup.force_encoding("utf-8").scrub! }
      @prepend_login, @suffix, @truncate_branch_only = prepend_login, suffix, truncate_branch_only
    end
  end
end
