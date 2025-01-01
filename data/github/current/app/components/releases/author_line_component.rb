# typed: true
# frozen_string_literal: true

module Releases
  class AuthorLineComponent < ApplicationComponent
    def initialize(release)
      @release = release
    end

    attr_reader :release

    def action
      # No release author means this is a plain git tag
      "tagged" unless release.author

      if release.new_record?
        release.tagged? ? "tagged" : "drafted"
      else
        release.draft? ? "drafted" : "released"
      end + " this"
    end
  end
end
