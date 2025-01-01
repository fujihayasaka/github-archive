# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class HydroRepositoryCreatedJob < Repositories::RepositoryHydroMessageJob
    extend T::Sig

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

      visibility_column_name = repository.public? ? :default_for_new_public_repos : :default_for_new_private_repos
      default_configuration = SecurityConfigurationDefault.find_by(
        :target => repository.owner,
        visibility_column_name => true
      )

      # Since the Hydro message doesn't contain an actor ID directly, we infer it based off the created_by_user:
      actor = repository.created_by_user

      if default_configuration.blank?
        business = repository.owner&.organization? ? repository.owner.business : nil
        return log_skip(:no_default_configuration) if business.nil?

        result = with_write do
          repository.setup_security_products_based_on_business_defaults(business, actor)
        end

        log_skip(:no_default_configs_nor_business_settings) if result.error == :no_business_defaults
        return
      end

      T.must(default_configuration.security_configuration).apply_to_repository(
        actor,
        repository.id,
        repository.owner_id,
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
        unless repository.present?
          return :repository_missing
        end
      rescue ActiveRecord::RecordNotFound
        return :repository_missing
      end

      # Nor can you enable them on an archived repository.
      if repository.archived?
        return :repository_archived
      end

      raise OwnerNotFoundError if repository.owner.nil?

      # Security Product Enablement isn't a thing for users:
      if repository.owner.user?
        return :repository_owner_is_user
      end

      nil
    end
  end
end
