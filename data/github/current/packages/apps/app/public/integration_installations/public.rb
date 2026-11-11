# typed: strict
# frozen_string_literal: true

module IntegrationInstallations
  module Public
    extend self

    METADATA = "metadata"

    sig { params(integration: Integration, repository: T.nilable(Repository)).returns(T.nilable(IntegrationInstallation)) }
    def on_repository(integration, repository)
      return unless repository.present?
      return unless repository.active?

      installation = integration.installations.find_by(target: repository.owner)
      return unless installation.present?

      options = {
        resource: METADATA,
        repository_ids: [repository.id],
      }

      if Repositories::Public.organization_owned?(repository)
        options[:organization] = repository.owner
      end

      return if installation.repository_ids(**options).none?

      installation
    end

    sig { params(target_ids: T::Array[Integer]).returns(T::Array[IntegrationInstallation]) }
    def on_all_repositories_for_targets(target_ids)
      return [] if target_ids.empty?

      installation_ids = ::Permissions::Service.actor_ids_granted_permission(
        actor_type: "IntegrationInstallation",
        subject_type: User.new.repository_resources.metadata.ability_type,
        subject_ids: target_ids,
        action: Permission.actions[:read]
      )

      IntegrationInstallation.where(id: installation_ids).to_a
    end

    sig do
      params(repository: Repositories::IRepository).returns(T::Boolean)
    end
    def user_installable_ci_integration_installations?(repository)
      IntegrationInstallation
      .user_installable
      .with_resources_on(subject: repository, resources: "checks", min_action: :write)
      .any?
    end
  end
end
