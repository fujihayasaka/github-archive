# typed: true
# frozen_string_literal: true
module Memex
  class ProjectsNewBannerComponent < ApplicationComponent
    REPO_PROJECT_BANNER = "repo_projects_beta_banner"
    PROJECT_BANNER = "projects_beta_banner"

    def initialize(display: :block)
      @display = display
    end

    def render?
      return false unless logged_in?

      dismissed_splash = current_user.dismissed_notice?(Memex::ProjectsNewSplashComponent::PROJECT_SPLASH)
      return dismissed_splash && \
        !current_user.dismissed_notice?(PROJECT_BANNER) unless is_repo_projects?

      splashes_dismissed = dismissed_splash || \
        current_user.dismissed_notice?(Memex::ProjectsNewSplashComponent::REPO_PROJECT_SPLASH)

      splashes_dismissed && !current_user.dismissed_notice?(REPO_PROJECT_BANNER)
    end

    memoize def path
      is_repo_projects? ? REPO_PROJECT_BANNER : PROJECT_BANNER
    end

    private

    memoize def is_repo_projects?
      current_repository.present?
    end

    def docs_url
      if GitHub.enterprise?
        version_number = GitHub.major_minor_version_number == "unknown" ? "latest" : GitHub.major_minor_version_number
        "https://docs.github.com/enterprise-server@#{version_number}/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects"
      else
        "https://docs.github.com/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects"
      end
    end
  end
end
