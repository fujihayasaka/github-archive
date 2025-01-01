# typed: true
# frozen_string_literal: true

module Releases
  class TagLandingPageComponent < ApplicationComponent
    include ReleasesHelper

    attr_reader :current_repository, :tag_as_release, :truncate_assets

    def initialize(current_repository, tag_as_release, truncate_assets: false)
      @current_repository = current_repository
      @tag_as_release = tag_as_release
      @truncate_assets = truncate_assets
    end
  end
end
