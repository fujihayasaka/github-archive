# typed: true
# frozen_string_literal: true

module PullRequests
  class BranchLabelComponent < ApplicationComponent

    attr_reader :repository, :branch, :prepend_login, :expandable, :extra_classes, :extra_link_classes, :link, :copy_button, :suffix, :branch_octicon, :octicon_classes, :truncate_branch_only

    def initialize(
      repository:,
      branch:,
      prepend_login: false,
      expandable: false,
      extra_classes: "",
      extra_link_classes: "",
      link: false,
      copy_button: false,
      suffix: "",
      branch_octicon: false,
      octicon_classes: "",
      truncate_branch_only: false)
      @repository, @branch, @prepend_login, @expandable, @extra_classes, @extra_link_classes, @link, @copy_button, @suffix, @branch_octicon,  @octicon_classes, @truncate_branch_only =
        repository, branch, prepend_login, expandable, extra_classes, extra_link_classes, link, copy_button, suffix, branch_octicon, octicon_classes, truncate_branch_only
    end

    def full_branch_name
      branch_name = branch.try { |s| s.dup.force_encoding("utf-8").scrub! }
      return branch_name unless repository

      repo_name = repository.name.try { |s| s.force_encoding("utf-8").scrub! }
      repo_owner = repository.owner_display_login.try { |s| s.force_encoding("utf-8").scrub! }

      if prepend_login && repository
        "#{repo_owner}:#{branch_name}"
      else
        branch_name
      end
    end

    def expandable_classes
      expandable ? "commit-ref css-truncate user-select-contain expandable" : ""
    end
  end
end
