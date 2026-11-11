# typed: true
# frozen_string_literal: true

module Rest
  class Preview
    # We use this value for the start year / start month when we don't yet know
    # when the preview will be available.
    UNAVAILABLE = 0

    attr_reader :name, :description, :code_name, :owning_teams, :start_year, :start_month
    def initialize(name:, description:, code_name:, owning_teams:, start_year:, start_month:)
      # The name of the feature the preview is for.
      #
      # E.g.:
      #   "reactions"
      @name = name.to_sym

      # A sentence describing what the feature flag enables.
      #
      # E.g.
      #
      @description = description

      # The superhero character that the media version is based on.
      #
      # E.g.
      #     "squirrel-girl"
      @code_name = code_name

      # An array of GitHub teams, written the way you would ping them in an issue.
      #
      # E.g.
      #     ["@github/some-team"]
      @owning_teams = owning_teams

      # The start of a preview is not when it was first implemented, but when we
      # started telling people (presumably outside of GitHub) to try it out. That
      # might be a blog post, or it might be the support team that passes a gist
      # with some docs in it to people who write in about a specific topic.  For
      # an internal-only preview it's when we decide that it's ready to be used.
      #
      # This value can be an approximation, once we know when (ish) we intend
      # to make the preview available to people.
      #
      # Leave both values as 0 until we know when it will be released.
      #
      # An integer representing the year.
      #
      # E.g.
      #
      #     2018
      @start_year = start_year
      # An integer representing the month.
      #
      # E.g.
      #
      #     8
      @start_month = start_month
    end

    # This is the version that gets passed as part of the HTTP version header.
    def media_version
      "#{code_name}-preview"
    end

    # Is this preview available to its target end-users yet?
    # Note: This is used purely for reporting purposes, not to control the feature in any way.
    def available?
      start_year != UNAVAILABLE && start_month != UNAVAILABLE
    end
  end
end
