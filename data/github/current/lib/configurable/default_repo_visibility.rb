# typed: false
# frozen_string_literal: true

module Configurable
  module DefaultRepoVisibility
    LEGACY_KEY = "default_private_repos".freeze
    KEY = "default_repo_visibility".freeze

    def set_default_repo_visibility(visibility, actor)
      raise ArgumentError unless ::Repository::VISIBILITIES.include?(visibility)
      return nil if !GitHub.public_repositories_available? && visibility == ::Repository::PUBLIC_VISIBILITY
      config.delete(LEGACY_KEY, actor)
      config.set!(KEY, visibility, actor)
    end

    def default_repo_visibility
      return "private" if config.enabled?(LEGACY_KEY)
      visibility = config.get(KEY)
      return visibility unless visibility.nil?
      return "internal" if GitHub.enterprise?
      "public"
    end
  end
end
