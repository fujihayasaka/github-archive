# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class HydroRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_products_enablement_repository_transferred

    retry_on_dirty_exit

    sig { void }
    def perform
      prev_owner_id = message.dig(:previous_owner, :id)
      previous_repository_security_configuration = RepositorySecurityConfiguration.find_by(repository_id: repository_id, organization_id: prev_owner_id)
      previous_security_configuration = previous_repository_security_configuration&.security_configuration
      owner = repository.owner

      if owner.nil?
        delete_previous_repository_security_configuration(previous_repository_security_configuration)
        log_skip(:repository_owner_is_missing) if owner.nil?
      elsif previous_security_configuration && previous_security_configuration.business? && owner.business == previous_security_configuration.target
        reapply_existing_security_configuration(previous_repository_security_configuration, previous_security_configuration, owner)
      else
        delete_previous_repository_security_configuration(previous_repository_security_configuration)
        return log_skip(:repository_owner_is_user) unless owner.is_a? Organization
        apply_default_security_configuration(owner)
      end
    end

    private

    sig do
      params(
        previous_repository_security_configuration: RepositorySecurityConfiguration,
        previous_security_configuration: SecurityConfiguration,
        owner: User
      ).void
    end
    def reapply_existing_security_configuration(previous_repository_security_configuration, previous_security_configuration, owner)
      return log_skip(:repository_owner_is_user) unless owner.is_a? Organization

      RepositorySecurityConfiguration.throttle_writes_with_retry do
        previous_repository_security_configuration.update!(organization: owner)
      end

      previous_security_configuration.apply_to_repository(
        T.must(actor),
        repository,
        owner,
        override_existing_config: true,
        reason: :repo_transfer
      )
    end

    sig { params(owner: Organization).void }
    def apply_default_security_configuration(owner)
      visibility = repository.public? ? :public : :private
      security_configuration_to_apply = SecurityConfigurationDefault.find_for(target: owner, visibility:).first&.security_configuration

      # If there is no default configuration, we don't want to do anything
      return log_skip(:no_default_configuration) unless security_configuration_to_apply

      # If there is a reason to skip, we don't want to do anything
      if reason = reason_to_skip
        log_skip(reason)
        return
      end

      security_configuration_to_apply.apply_to_repository(
        T.must(actor),
        repository,
        owner,
        reason: :repo_transfer
      )
    end

    sig { params(previous_repository_security_configuration: T.nilable(RepositorySecurityConfiguration)).void }
    def delete_previous_repository_security_configuration(previous_repository_security_configuration)
      if previous_repository_security_configuration
        RepositorySecurityConfiguration.throttle_writes_with_retry do
          # Delete the previous owner's configuration if it exists
          previous_repository_security_configuration.destroy
        end
      end
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      actor = if actor_id.is_a?(Integer) && actor_id > 0
        User.find_by(id: actor_id)
      else
        repository.created_by_user || repository.owner&.admins&.first
      end
    end

    sig { params(reason: Symbol).void }
    def log_skip(reason)
      GitHub.logger.info(
        "Skipping SecurityProductEnablement processing on repo transfer",
        reason:
      )
    end

    sig { returns(T.nilable(Symbol)) }
    def reason_to_skip
      # Nor can you enable them on an archived repository.
      if repository.archived?
        return :repository_archived
      end

      nil
    end
  end
end
