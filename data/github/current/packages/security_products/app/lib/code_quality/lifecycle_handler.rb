# typed: strict
# frozen_string_literal: true

module CodeQuality
  class LifecycleHandler
    include GitHub::Memoizer

    sig { params(repository: Repository, actor_id: T.nilable(Integer)).void }
    def initialize(repository:, actor_id:)
      @repository = repository
      @actor_id = actor_id
    end

    # Handles enterprise lifecycle events (org add/remove/transfer/upgrade) and Repo transfer events.
    # Disables CQ when there is no billable owner or access policy disallows CQ otherwise republishes the current state
    sig { params(is_repo_transfer: T::Boolean).void }
    def handle_event!(is_repo_transfer: false)
      unless code_quality_enabled?
        publish_state(enabled: false)
        return
      end


      if should_disable?
        if is_repo_transfer
          # TODO: Check for org level enablement on the new owner org. If org-level enablement is off, we should disable CQ.
        end
        disable!
      else
        publish_state(enabled: true)
      end
    end

    private

    sig { returns(T::Boolean) }
    def code_quality_enabled?
      return false if @repository.deleted?

      CodeQualityEnablement.new(@repository).enabled?
    end

    sig { void }
    def disable!
      return unless FeatureFlag.vexi.enabled?(:code_quality_lifecycle_events_force_disable, @repository, @repository.owner, @repository.business, default: false)

      current_actor = actor
      unless current_actor
        GitHub.logger.warn(
          "Skipping CQ lifecycle disable: no actor resolvable",
          "code.namespace": self.class.name,
          "gh.repo.id": @repository.id,
        )
        return
      end

      # skip_instrumentation: CodeQualityEnablement#on_disable calls publish_instrumentation internally,
      # which publishes the RepositoryUpdate hydro event, so we skip ServiceManager-level instrumentation.
      result = SecurityProduct::ServiceManager.new(@repository)
        .toggle_services(current_actor, services_to_disable: [[:code_quality, { skip_if_disabled: true }]], skip_instrumentation: true)

      raise StandardError.new("Failed to disable CQ lifecycle: #{result.error}") if result.error?
    end

    sig { params(enabled: T::Boolean).void }
    def publish_state(enabled:)
      CodeQuality::RepositoryUpdatePublisher.publish_repository(
        repo: @repository,
        code_quality_enabled: enabled,
      )
    end

    # (OrganizationRemove/Transfer) Disable when the org no longer billable ( has no business or team plan )
    # OrganizationUpgrade/Add keep the org in the same enterprise, so owner.business
    # remains truthy and we just re-publish billing state unless access policy disallows CQ.
    sig { returns(T::Boolean) }
    def should_disable?
      owner = @repository.owner
      return true unless owner&.organization?

      return true if Licensing::Customer.id_for(owner).nil?

      # Disable if access policy config disallows CQ enablement
      return true unless policy_allows_code_quality_enablement?

      false
    end

    sig { returns(T.nilable(User)) }
    memoize def actor
      actor = if @actor_id.is_a?(Integer) && @actor_id > 0
        User.find_by(id: @actor_id)
      end

      actor || @repository.created_by_user || (@repository.owner.respond_to?(:admins) ? T.must(@repository.owner).admins.first : nil)
    end

    sig { returns(T::Boolean) }
    def policy_allows_code_quality_enablement?
      CodeQualityAccessPolicyConfig.new(@repository).policy_allows_code_quality_enablement?
    end
  end
end
