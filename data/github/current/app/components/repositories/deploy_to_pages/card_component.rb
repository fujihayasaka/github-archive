# typed: strict
# frozen_string_literal: true

class Repositories::DeployToPages::CardComponent < ApplicationComponent
  FRAMEWORKS = T.let({
    "vite" => "Vite app",
    "astro" => "Astro app",
    "nextjs" => "Next.js app",
    "gatsby" => "Gatsby site",
    "nuxtjs" => "Nuxt.js app",
    "eleventy" => "Eleventy site",
  }.freeze, T::Hash[String, String])

  NOTICE_NAME = "deploy_to_pages_banner"

  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(User) }
  attr_reader :user

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :system_arguments

  sig { params(repository: Repository, user: User, system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(repository:, user:, **system_arguments)
    @repository = repository
    @user = user
    @system_arguments = system_arguments
    @system_arguments[:mb] ||= 2
    @system_arguments[:p] ||= 3
    @system_arguments[:border] = true unless system_arguments.key?(:border)
    @system_arguments[:border_radius] ||= 2
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless FeatureFlag.vexi.enabled?(:pages_deploy_flow, user, default: false)
    return false unless repository.can_see_deployments?(user)
    return false unless repository.writable_by?(user)
    return false if repository.ranked_active_deployment_environments.any?
    return false if user.dismissed_repository_notice?(NOTICE_NAME, repository_id: repository.id)
    return false unless detected_stack[:framework].present? && detected_stack[:package_manager].present?

    true
  end

  sig { returns(String) }
  def description
    framework = detected_stack[:framework]
    framework_name = framework && FRAMEWORKS[framework]
    "Deploy your #{framework_name || "project"} to GitHub Pages in a matter of minutes"
  end

  sig { returns(String) }
  memoize def deploy_path
    helpers.deploy_path(repository.owner_display_login, repository, framework: detected_stack[:framework], package_manager: detected_stack[:package_manager])
  end

  sig { returns(T::Hash[String, String]) }
  def configure_button_analytics
    helpers.analytics_click_attributes(
      category: "Deploy to Pages",
      action: "click_to_configure",
      label: "ref_cta:configure;ref_loc:repo_sidebar;repo:#{repository.id}",
    )
  end

  private

  sig { returns(T::Hash[Symbol, T.nilable(String)]) }
  memoize def detected_stack
    helpers.detect_stack(repository)
  end
end
