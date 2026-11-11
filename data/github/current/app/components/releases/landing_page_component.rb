# typed: true
# frozen_string_literal: true

module Releases
  class LandingPageComponent < ApplicationComponent
    include ReleasesHelper
    attr_reader :release, :current_repository, :current_user

    def initialize(release, current_repository, current_user)
      @release = release
      @current_repository = current_repository
      @current_user = current_user
    end

    def is_latest?
      return false if @release.prerelease?
      @release == latest_release
    end

    memoize def latest_release
      Releases::Public.latest_for_repository(@current_repository, @current_user)
    end

    def writable?
      @current_repository.writable? && @current_repository.pushable_by?(@current_user)
    end
  end
end
