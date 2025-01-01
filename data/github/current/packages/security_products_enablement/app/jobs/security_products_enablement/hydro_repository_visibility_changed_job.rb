# typed: true
# frozen_string_literal: true

# HydroRepositoryVisibilityChangedJob handles a few important steps
# 1. Generally applying any enforced default security configurations
# 2. Preventing future situations where we leave the config values behind that cause
# surprise billing. For example:
#   Given a public repo in a free org
#   Then it goes private
#   Then the org is upgraded to a Team plan
#   And now this repo is considered "billable".
# We want to do the right thing and cleanup config values unless the repo was intended to keep the feature.
# This is why the logic around #2 also does not check for any kind of advanced security purchase state
#
# Additionally, we don't need to look at top-level business defaults as those are specific to repo creation
# and agnostic to the repository's visibility.
# If there is no configuration, we'll turn everything off.
# If there is one, the configuration will handle turning enabled products off.
module SecurityProductsEnablement
  class HydroRepositoryVisibilityChangedJob < Repositories::RepositoryHydroMessageJob
    include SecretScanning::Features::FeatureFlagHelper

    queue_as :hydro_security_products_enablement_repository_visibility_changed

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
      unless default_configuration.blank?
        # Applying the security configuration will turn off anything that's enabled as well
        # We don't need to do anything further
        res = T.must(default_configuration.security_configuration).apply_to_repository(
          repository,
          actor:,
          reason: :repo_creation, # This allows some policies to be overridden
          override_existing_config: true, # Override any currently attached config
        )
        return res ? log_result(:applied_default_to_repository) : log_result(:unsuccessful_attach_to_repository)
      end

      # Disable if we are going private/internal and the repo was not already private/internal
      going_private = [:PRIVATE, :INTERNAL].include?(message.dig(:new_visibility))
      from_private = [:PRIVATE, :INTERNAL].include?(message.dig(:old_visibility))
      should_disable_paid_features = going_private && !from_private

      return log_skip(:should_not_disable_paid_features) unless should_disable_paid_features
      return log_skip(:on_enterprise) if GitHub.enterprise?
      params = {}

      params[:advanced_security_enabled] = "0" if repository.advanced_security_enabled?
      params[:code_security_enabled] = "0" if !repository.advanced_security_products_bundled? && SecurityProduct::CodeSecurity.new(repository).enabled?
      params[:token_scanning_enabled] = "0" if SecurityProduct::TokenScanning.new(repository).enabled?

      # If this is empty, then it means there was a config that wanted everything on
      return log_result(:no_params_to_toggle) if params.empty?

      # Note that this may fail for a variety of reasons like enterprise policies. This is a best effort attempt
      # to turn off paid features
      result = with_write do
        SecurityProduct::ServiceManager.new(repository).toggle_services_with_form_inputs(actor, params:, skip_instrumentation: true)
      end
      log_result(result.error? ? :failed_to_toggle_features : :successfully_toggled_features)
    end

    private

    sig { params(reason: Symbol).void }
    def log_skip(reason)
      GitHub.logger.info(
        "Skipping SecurityProductEnablement processing on repo visibility change",
        reason:
      )
    end

    sig { params(reason: Symbol).void }
    def log_result(reason)
      GitHub.logger.info(
        "Finished SecurityProductEnablement processing for repo visibility change",
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
