# typed: true
# frozen_string_literal: true

module Blobs
  class EditDropdownMenuComponent < ApplicationComponent
    include DesktopHelper

    attr_reader :edit_tooltip, :current_branch_or_tag_name, :branch, :repo, :edit_enabled, :edit_path, :github_dev_enabled, :dropdown_tracking_attributes, :github_dev_link_tracking_attributes

    def initialize(edit_tooltip:, current_branch_or_tag_name:, branch:, repo:, edit_enabled:, edit_path:, github_dev_enabled:, dropdown_tracking_attributes:, github_dev_link_tracking_attributes:)
      @edit_tooltip = edit_tooltip
      @current_branch_or_tag_name = current_branch_or_tag_name
      @branch = branch
      @repo = repo
      @edit_enabled = edit_enabled
      @edit_path = edit_path
      @github_dev_enabled = github_dev_enabled
      @dropdown_tracking_attributes = dropdown_tracking_attributes
      @github_dev_link_tracking_attributes = github_dev_link_tracking_attributes
    end

    def clone_url
      app_clone_url(repo, nil, current_branch_or_tag_name, path_string)
    end
  end
end
