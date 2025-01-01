# typed: true
# frozen_string_literal: true

module Memex
  class ProjectsNewSplashComponent < ApplicationComponent
    REPO_PROJECT_SPLASH = "repo_projects_beta_splash"
    PROJECT_SPLASH = "projects_beta_splash"

    def render?
      return false unless logged_in?

      not_dismissed_splash = !current_user.dismissed_notice?(PROJECT_SPLASH)
      return not_dismissed_splash unless is_repo_projects?

      !current_user.dismissed_notice?(REPO_PROJECT_SPLASH) && not_dismissed_splash
    end

    memoize def path
      is_repo_projects? ? REPO_PROJECT_SPLASH : PROJECT_SPLASH
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
