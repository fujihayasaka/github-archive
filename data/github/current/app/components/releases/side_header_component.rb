# typed: true
# frozen_string_literal: true

module Releases
  class SideHeaderComponent < ApplicationComponent
    def initialize(release, repository, unqualified_name_conflict: false, highlights: nil)
      @release = release
      @current_repository = repository
      @unqualified_name_conflict = unqualified_name_conflict
      @highlights = highlights
    end

    attr_reader :release, :current_repository, :highlights

    def release_commit_path
      commit_path release.tag.commit, current_repository
    end

    def tag_path
      tree_path "", @unqualified_name_conflict ? release.tag.qualified_name_for_display : release.tag.name_for_display
    end

    def display_tag_name
      if @highlights&.fetch("tag_name", nil)&.any?
        hl_tag_name = @highlights&.fetch("tag_name").first
        sanitize hl_tag_name, tags: %w(mark)
      else
        release.tag.name_for_display
      end
    end
  end
end
