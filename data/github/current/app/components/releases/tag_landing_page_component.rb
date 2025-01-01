# typed: true
# frozen_string_literal: true

module Releases
  class TagLandingPageComponent < ApplicationComponent
    include ReleasesHelper

    attr_reader :current_repository, :tag_as_release

    def initialize(current_repository, tag_as_release)
      @current_repository = current_repository
      @tag_as_release = tag_as_release
    end
  end
end
