# typed: true
# frozen_string_literal: true

module Releases
  class TagHistoryComponent < ApplicationComponent
    include ReleasesHelper
    include CachedOcticonHelper

    attr_reader :current_repository, :tags_as_releases

    def initialize(tags_as_releases, current_repository, writable:, deletable_tags:)
      @current_repository = current_repository
      @tags_as_releases = tags_as_releases
      @writable = writable
      @deletable_tags = deletable_tags
    end

    def writable?
      @writable
    end

    def tag_deletable?(tag_as_release)
      @deletable_tags.include?(tag_as_release)
    end

    def view
      view = Releases::TimelineView.new(current_repository, current_user, tags_as_releases)
    end
  end
end
