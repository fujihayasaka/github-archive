# typed: true
# frozen_string_literal: true

module Dependabot
  class PausedUpdatesBannerComponent < ApplicationComponent
    attr_reader :repository

    include UrlHelper

    def initialize(repository:, interactive: false)
      @repository = repository
      @interactive = interactive
    end

    def docs_link
      "#{GitHub.help_url}/code-security/dependabot/working-with-dependabot/managing-pull-requests-for-dependency-updates"
    end

    def dependabot_prs_link
      repository_path(@repository) + "/pulls/app%2Fdependabot"
    end

    def render?
      self.class.render?(@repository)
    end

    def self.render?(repository)
      (repository.vulnerability_updates_enabled? || repository.dependabot_version_updates_enabled?) && repository.dependabot_updates_paused?
    end
  end
end
