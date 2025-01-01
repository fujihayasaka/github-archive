# typed: true
# frozen_string_literal: true

module Dependabot
  class PausedUpdatesPullRequestBannerComponent < ApplicationComponent
    attr_reader :repository

    include UrlHelper

    def initialize(pull_request:, repository:)
      @pull_request = pull_request
      @repository = repository
    end

    def docs_link
      "#{GitHub.help_url}/code-security/dependabot/dependabot-security-updates/about-dependabot-security-updates#about-automatic-deactivation-of-dependabot-updates"
    end

    def dependabot_prs_link
      repository_path(@repository) + "/pulls/app%2Fdependabot"
    end

    private

    def render?
      return false unless @pull_request.open?
      return false unless pull_author_is_dependabot?
      return false unless writable?

      @repository.dependabot_updates_paused?
    end

    def writable?
      return true unless GitHub.flipper[:dependabot_paused_write_access_check].enabled?

      @repository.writable_by?(current_user)
    end

    def pull_author_is_dependabot?
      @pull_request.user == GitHub.dependabot_github_app_bot
    end
  end
end
