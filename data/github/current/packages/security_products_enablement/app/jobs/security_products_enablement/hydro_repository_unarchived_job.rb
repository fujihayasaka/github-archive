# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class HydroRepositoryUnarchivedJob < Repositories::RepositoryHydroMessageJob
    include GitHub::Memoizer
    include RepositoryHydroMessageJobTenantContext

    OwnerNotFoundError = Class.new(StandardError)

    queue_as :hydro_security_products_enablement_repository_unarchived

    retry_on_dirty_exit

    sig { void }
    def perform
      if reason = reason_to_skip
        log_skip(reason)
        return
      end

      # If any of these are nil, the skip_reason guard above will prevent us from reaching this
      # so we can safely unwrap these optionals
      security_configuration = T.must_because(self.security_configuration) { "checked above" }

      owner = repository.owner
      raise OwnerNotFoundError if owner.nil?
      return log_skip(:repository_owner_is_user) unless owner.is_a? Organization

      actor = actor_id.is_a?(Integer) && actor_id > 0 ? User.find_by(id: actor_id) : repository.created_by_user

      security_configuration.apply_to_repository(repository, actor:, reason: :repo_unarchived)
    end

    sig { params(reason: Symbol).void }
    def log_skip(reason)
      GitHub.logger.info(
        "Skipping SecurityProductEnablement processing on repo unarchived",
        reason:
      )
    end

    sig { returns(T.nilable(Symbol)) }
    def reason_to_skip
      begin
        repository
      rescue ActiveRecord::RecordNotFound
        return :repository_missing
      end

      if repository.archived?
        return :repository_archived
      end

      if repository_security_configuration.nil?
        return :repository_security_configuration_missing
      end

      unless [:attached, :enforced, :failed].include?(repository_security_configuration&.state&.to_sym)
        return :repository_security_configuration_ineligible
      end

      if security_configuration.nil?
        return :security_configuration_missing
      end

      nil
    end

    sig { returns(T.nilable(SecurityConfiguration)) }
    memoize def security_configuration
      repository_security_configuration&.security_configuration
    end

    sig { returns(T.nilable(RepositorySecurityConfiguration)) }
    memoize def repository_security_configuration
      repository.repository_security_configuration
    end
  end
end
