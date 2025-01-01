# typed: true
# frozen_string_literal: true

require "dependency_graph/repository_manifests_provider"

module Repository::DependenciesDependency
  extend T::Helpers
  requires_ancestor { Repository }

  include GitHub::Tracing
  include SecretScanning::Features::FeatureFlagHelper

  class ManifestsNotDetectedError < StandardError; end

  # Upper bound on manifest file paths that will be persisted.
  MAX_MANIFEST_FILES_DEFAULT = 150
  # There are some repositories that we need to parse more than 150
  # manifests for, e.g. public repos that contain the code/manifests
  # to open-source libraries we want to map in the dependency graph
  # The upper bound we choose is controlled by the
  # `:dependency_graph_max_manifests_high` feature flag.
  MAX_MANIFEST_FILES_HIGH = 600

  # Does this repository have parsed dependency manifests?
  # This information is obtained by querying the Dependency Graph API.
  trace_method :has_manifests?
  def has_manifests?(only_static_manifests: false)
    response = repository_manifests_provider
               .has_manifests(repository_id: self.id, only_static_manifests: only_static_manifests)[:response]
    response.has_manifests
  rescue DependencyGraph::BaseTwirpClient::NotFoundError
    # 404 in this case means that either:
    #  - the given repository doesn't exist
    #  - manifest detection hasn't run yet, or
    #  - it has but there are no manifests.
    # In any case, we should return false.
    false
  rescue DependencyGraph::BaseTwirpClient::Error => error
    # Failbot reporting should be done in DependencyGraph::BaseTwirpClientHandler
    GitHub.logger.error("Error calling Dependency Graph has_manifests?", {
      "code.function" => "DependenciesDependency.has_manifests?",
      "exception.message" => error.message,
      "exception.type" => error.class.name,
      "gh.repo.id" => self.id
    })
    raise error
  end

  # Public: Is this repository opted in to the Dependency Graph preview? The
  #         Dependency Graph keeps new language support under a preview flag,
  #         and this method tells us whether the current repository is opted in.
  #
  # Returns a Boolean.
  def dependency_graph_preview?
    self.feature_enabled?(:dependency_graph_preview, memoize: false) || GitHub.flipper[:dependency_graph_preview].enabled?(self.owner)
  end

  # Public: Is Dependency Review enabled for this repository?
  #
  # Returns a Boolean
  def dependency_review_enabled?
    return @dependency_review_enabled if defined?(@dependency_review_enabled)
    return @dependency_review_enabled = false unless dependency_graph_enabled?
    @dependency_review_enabled = code_security_features_usable?
  end

  # Internal: Maximum number of manifests we'll parse for this repo.
  #           There's a default value, but we make exceptions via feature flag
  # Returns an Integer
  def max_manifest_files
    return MAX_MANIFEST_FILES_DEFAULT if !GitHub.enterprise? && self.owner.blank?

    if GitHub.enterprise? \
      || self.feature_enabled?(:dependency_graph_max_manifests_high, memoize: false) \
      || GitHub.flipper[:dependency_graph_max_manifests_high].enabled?(self.owner)
      MAX_MANIFEST_FILES_HIGH
    elsif T.cast(self.owner, User::BillingDependency).business_plus? \
      && (self.feature_enabled?(:dependency_graph_disable_ghec_limits, memoize: false) \
      || GitHub.flipper[:dependency_graph_disable_ghec_limits].enabled?(self.owner))
      MAX_MANIFEST_FILES_HIGH
    else
      MAX_MANIFEST_FILES_DEFAULT
    end
  end

  def enable_dependency_graph(actor:)
    T.bind(self, Repository)
    res, _ = SecurityProduct::DependencyGraph.new(self).enable(actor: actor)
    res
  end

  def disable_dependency_graph(actor:)
    T.bind(self, Repository)
    res, _ = SecurityProduct::DependencyGraph.new(self).disable(actor: actor)
    res
  end

  def dependency_graph_enabled?
    # Checks if Dependency Graph is enabled for the given actor
    T.bind(self, Repository)
    GitHub.dependency_graph_enabled? && SecurityProduct::DependencyGraph.new(self).enabled?
  end

  def dependency_graph_autosubmission_action_enabled?
    T.bind(self, Repository)
    SecurityProduct::DependencyGraphAutosubmitAction.new(self).enabled?
  end

  private

  def repository_manifests_provider
    @repository_manifests_provider ||= DependencyGraph::RepositoryManifestsProvider.new
  end
end
