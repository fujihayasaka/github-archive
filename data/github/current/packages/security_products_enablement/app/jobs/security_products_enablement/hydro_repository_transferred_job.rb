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
      elsif should_reapply_existing_configuration?(previous_security_configuration, owner, prev_owner_id)
        reapply_existing_security_configuration(T.must(previous_repository_security_configuration), T.must(previous_security_configuration), owner)
      else
        delete_previous_repository_security_configuration(previous_repository_security_configuration)
        return log_skip(:repository_owner_is_user) unless owner.is_a? Organization
        apply_default_security_configuration_or_disable_features(owner, prev_owner_id)
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
        previous_repository_security_configuration.update!(user: owner)
      end

      previous_security_configuration.apply_to_repository(
        repository,
        actor: T.must(actor),
        override_existing_config: true,
        reason: :repo_transfer
      )
    end

    sig { params(owner: Organization, prev_owner_id: T.untyped).void }
    def apply_default_security_configuration_or_disable_features(owner, prev_owner_id)
      visibility = repository.public? ? :public : :private
      security_configuration_to_apply = SecurityConfigurationDefault.find_for(target: owner, visibility:).first&.security_configuration

      # If there is no default configuration, check if we should disable paid features
      unless security_configuration_to_apply
        if should_disable_paid_features?(owner, prev_owner_id)
          disable_paid_security_features
          return GitHub.logger.info(
            "Disabled paid security features on repo transfer",
            reason: :no_default_configuration_disabled_paid_features
          )
        else
          return log_skip(:no_default_configuration)
        end
      end

      # If there is a reason to skip, we don't want to do anything
      if reason = reason_to_skip
        log_skip(reason)
        return
      end

      security_configuration_to_apply.apply_to_repository(
        repository,
        actor: T.must(actor),
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

    sig { params(result: Symbol).void }
    def log_result(result)
      GitHub.logger.info(
        "Paid security features toggled for SecurityProductEnablement on repo transfer",
        result: result,
        repository_id: repository_id
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

    sig do
      params(
        previous_security_configuration: T.nilable(SecurityConfiguration),
        owner: User,
        prev_owner_id: T.untyped
      ).returns(T::Boolean)
    end
    def should_reapply_existing_configuration?(previous_security_configuration, owner, prev_owner_id)
      return false unless previous_security_configuration
      return false unless previous_security_configuration.business?
      return false unless owner.business == previous_security_configuration.target

      true
    end

    sig { params(owner: Organization, prev_owner_id: T.untyped).returns(T::Boolean) }
    def should_disable_paid_features?(owner, prev_owner_id)
      # Check if billable entities are different
      previous_owner = User.find_by(id: prev_owner_id)
      return false unless previous_owner

      owner.billable_owner != previous_owner.billable_owner
    end

    sig { void }
    def disable_paid_security_features
      GitHub.logger.info(
        "Disabling paid security features due to repository transfer to different billing entity",
        repository_id: repository_id
      )
      params = {}

      params[:advanced_security_enabled] = "0" if repository.advanced_security_enabled?
      params[:code_security_enabled] = "0" if !repository.advanced_security_products_bundled? && SecurityProduct::CodeSecurity.new(repository).enabled?
      params[:token_scanning_enabled] = "0" if SecurityProduct::TokenScanning.new(repository).enabled?

      return log_result(:no_params_to_toggle) if params.empty?

      # Note that this may fail for a variety of reasons like enterprise policies. This is a best effort attempt
      # to turn off paid features
      result = with_write do
        SecurityProduct::ServiceManager.new(repository).toggle_services_with_form_inputs(T.must(actor), params:, skip_instrumentation: true)
      end
      log_result(result.error? ? :failed_to_toggle_features : :successfully_toggled_features)
    end
  end
end
