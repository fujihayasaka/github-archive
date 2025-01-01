# typed: strict
# frozen_string_literal: true

class DashboardFeed::LearnComponent < ApplicationComponent
  TUTORIAL_PROJECTS = T.let([
    {
      id: SecureRandom.uuid,
      name: "Introduction to GitHub",
      description: "Get started using GitHub in less than an hour.",
      url: "https://github.com/skills/introduction-to-github"
    },
    {
      id: SecureRandom.uuid,
      name: "GitHub Pages",
      description: "Create a site or blog from your GitHub repositories with GitHub Pages.",
      url: "https://github.com/skills/github-pages"
    },
    {
      id: SecureRandom.uuid,
      name: "Code with Copilot",
      description: "Develop with AI-powered code suggestions using GitHub Copilot, Codespaces, and VS Code.",
      url: "https://github.com/skills/copilot-codespaces-vscode"
    },
    {
      id: SecureRandom.uuid,
      name: "Hello GitHub Actions",
      description: "Create a GitHub Action and use it in a workflow.",
      url: "https://github.com/skills/hello-github-actions"
    }
  ].freeze, T::Array[T::Hash[String, String]])

  private

  sig { returns(String) }
  def notice_name
    UserNotice::ZERO_USER_DASHBOARD_LEARN_NOTICE
  end

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.enterprise?

    !current_user.dismissed_notice?(notice_name)
  end
end
