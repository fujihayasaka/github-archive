# typed: true
# frozen_string_literal: true

module DockerHelper
  extend ActiveSupport::Concern

  # List of popular public Docker repositories that we track
  POPULAR_DOCKER_REPOS = %w[
    awesome-compose
    compose
    kitematic
    labs
    docker-bench-security
    dockercraft
    docker-py
    machine
    cli
    build-push-action
    genai-stack
    docs
    buildx
    getting-started
    docker-install
    for-mac
    libchan
    for-win
    roadmap
    app
    compose-on-kubernetes
    login-action
    docker-credential-helpers
    setup-buildx-action
    metadata-action
    libkv
    for-linux
    libcompose
    welcome-to-docker
    setup-qemu-action
  ].freeze

  def recently_starred_docker_repo?(user)
    return false unless user

    # First get all the repositories owned by docker using the domain API
    docker_repos = POPULAR_DOCKER_REPOS.map do |repo_name|
      Repositories.domain.by_owner_and_repo_names("docker", repo_name)
    end.compact.map(&:id).compact

    # Then find if the user has starred any of these repos
    star_ids = Stars.domain.user_starred_repository_ids(user.id, repo_ids: docker_repos)
    star_ids.any?
  end
end
