# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class HydroRepositoryCreatedJob < Repositories::RepositoryHydroMessageJob
    queue_as :hydro_security_products_enablement_repository_created

    OwnerNotFoundError = Class.new(StandardError)

    retry_on_dirty_exit
    retry_on OwnerNotFoundError, delay: :polynomially_longer, max_retries: 3

    sig { void }
    def perform
      if reason = reason_to_skip
        log_skip(reason)
        return
      end

      owner = repository.owner
      raise OwnerNotFoundError if owner.nil?
      return log_skip(:repository_owner_is_user) unless owner.is_a? Organization

      visibility = repository.public? ? :public : :private
      default_configuration = SecurityConfigurationDefault.find_for(target: owner, visibility:).first

      actor = actor_id.is_a?(Integer) && actor_id > 0 ? User.find_by(id: actor_id) : repository.created_by_user

      if default_configuration.blank?
        business = owner.business
        return log_skip(:no_default_configuration) if business.nil?

        result = with_write do
          repository.setup_security_products_based_on_business_defaults(business, actor)
        end

        log_skip(:no_default_configs_nor_business_settings) if result.error == :no_business_defaults
        return
      end

      T.must(default_configuration.security_configuration).apply_to_repository(
        repository,
        actor:,
        reason: :repo_creation,
      )
    end

    private

    sig { params(reason: Symbol).void }
    def log_skip(reason)
      GitHub.logger.info(
        "Skipping SecurityProductEnablement processing on repo creation",
        reason:
      )
    end

    sig { returns(T.nilable(Symbol)) }
    def reason_to_skip
      # You can't enable security products on a repository that doesn't exist.
      begin
        repository
      rescue ActiveRecord::RecordNotFound
        return :repository_missing
      end

      # Nor can you enable them on an archived repository.
      if repository.archived?
        return :repository_archived
      end

      nil
    end
  end
end
