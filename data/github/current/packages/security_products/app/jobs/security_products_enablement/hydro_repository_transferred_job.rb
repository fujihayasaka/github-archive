# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class HydroRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_products_enablement_repository_transferred

    retry_on_dirty_exit

    sig { void }
    def perform
      prev_owner_id = message.dig(:previous_owner, :id)
      RepositorySecurityConfiguration.throttle_writes_with_retry do
        # Delete the previous owner's configuration if it exists
        RepositorySecurityConfiguration.find_by(repository_id: repository_id, organization_id: prev_owner_id)&.destroy
      end

      repository = T.must(Repositories::Public.get_active_or_deleted!(repository_id))
      return unless repository.present?

      visibility_column_name = repository.public? ? :default_for_new_public_repos : :default_for_new_private_repos

      default_configuration = SecurityConfigurationDefault.find_by(
        :target => repository.owner,
        visibility_column_name => true
      )

      # If there is no default configuration, we don't want to do anything
      return log_skip(:no_default_configuration) if default_configuration.blank?

      # If there is a reason to skip, we don't want to do anything
      if reason = reason_to_skip
        log_skip(reason)
        return
      end

      # Since the Hydro message doesn't contain an actor ID directly, we infer it based off the created_by_user
      # or we default to the repository owner's first admin.
      actor = repository.created_by_user || repository.owner&.admins&.first

      T.must(default_configuration.security_configuration).apply_to_repository(
        actor,
        T.must(repository.id),
        repository.owner_id,
        reason: :repo_transfer
      )
    end

    private

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

      # Security Product Enablement isn't a thing for users:
      if repository.owner.user?
        return :repository_owner_is_user
      end

      nil
    end
  end
end
