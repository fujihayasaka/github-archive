# typed: false
# frozen_string_literal: true

class Organization::ProfileReadme::Base
  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  # /profile/README.md
  def readme
    return @readme if defined?(@readme)
    @readme = fetch_readme&.sync
  end

  # Check whether the org member profile readme should be visible to the current user
  def visible?
    if defined?(@visible)
      return @visible
    end

    @visible = check_visibility
  end

  def async_visible?
    return Promise.resolve(@visible) if defined?(@visible)
    async_repository.then do
      @visible = check_visibility
    end
  end

  private

  def track_time
    timer = Timer.start
    result = yield
    timer.stop

    GitHub.dogstats.distribution(
      "profile_readme_check",
      timer.elapsed_ms,
      tags: [
        "readme_found:#{result}",
        "type:organization",
        "visibility:#{type}"
      ]
    )
    result
  end

  def check_visibility
    # Track the time it takes to check if a readme is visible
    track_time do
      next false if organization.spammy?
      next false unless repository
      next false unless readme
      next false if readme.data.blank?
      # As of now, it's necessary to check both disabled? methods.
      # See https://github.com/github/github/pull/148922/files#r452507975
      # for details
      next false if repository.access.disabled?
      next false if repository.disabled?
      true
    end
  end
end
