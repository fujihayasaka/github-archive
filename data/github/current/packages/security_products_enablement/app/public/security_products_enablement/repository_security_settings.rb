# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  module RepositorySecuritySettings
    # Dependency Graph is an early adopter of RepositorySecuritySettings, so these accessors
    # provide a minimal way of accessing the RepositorySecuritySetting model through public
    # methods.
    #
    # This will likely be replaced with an idiomatic accessor path that is better integrated
    # with the SecurityProductsEnablement::Domain, but this is good enough for now.
    sig { params(repository: ::Repository).returns(T::Boolean) }
    def self.dependency_graph_enabled?(repository)
      RepositorySecuritySetting.where(repository: repository).dependency_graph.enabled.exists?
    end

    sig { params(repository: ::Repository).void }
    def self.enable_dependency_graph!(repository)
      RepositorySecuritySetting.upsert(
        { repository_id: repository.id, feature: :dependency_graph, state: :enabled },
        on_duplicate: :update
      )
    end

    sig { params(repository: ::Repository).void }
    def self.disable_dependency_graph!(repository)
      RepositorySecuritySetting.where(repository: repository).dependency_graph.enabled.destroy_all
    end
  end
end
