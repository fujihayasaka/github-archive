# typed: strict
# frozen_string_literal: true

# When the UpdateGraphEventHandler processes a message from a Repository
# we have not seen before, we need to request a JIT (Just-In-Time) install
# before the repository is available for updates.
#
# This class uses the GitHub::Twirp::AppInstall client to request an
# installation is created, then calls back to UpdateGraphEventHandler to
# continue processing the graph update.
module UpdateGraph
  class OnboardRepositoryJob < ApplicationJob
    extend T::Sig

    queue_as :graph_onboard_repository
    default_retries_for_idempotent_jobs

    class InstallFailed < StandardError; end
    class InstallRefused < StandardError; end

    T.unsafe(self).include ActiveJob::Retry.new(
      strategy: RateLimitBackoffStrategy.new(
        limit: 5,
        retryable_exceptions: [
          *GitHubHelpers::RETRYABLE_ERRORS,
          GitHub::Twirp::AppInstall::Error,
        ],
      ),
    )

    sig do
      params(
        owner: HydroHandlers::GitHub::User,
        repository: HydroHandlers::GitHub::Repository,
        graph_changes: HydroHandlers::DependencyGraph::GraphChanges
      ).void
    end
    def perform(owner:, repository:, graph_changes:)
      Dependabot::Exceptions.push(
        "gh.owner.id": owner.id,
        "gh.repo.id": repository.id,
      )

      if use_global_app_for_graph_jobs?(owner)
        setup_account_with_global_app(owner)
        create_graph_update_job(owner: owner, repository: repository, graph_changes: graph_changes)
      else
        owner_with_install = setup_account_with_installation(owner: owner, repository: repository)
        create_graph_update_job(owner: owner_with_install, repository: repository, graph_changes: graph_changes)
      end
    rescue InstallRefused
      # Nothing to do.
    end

    private

    sig do
      params(
        owner: HydroHandlers::GitHub::User,
        repository: HydroHandlers::GitHub::Repository,
        graph_changes: HydroHandlers::DependencyGraph::GraphChanges
      ).void
    end
    def create_graph_update_job(owner:, repository:, graph_changes:)
      UpdateGraphEventHandler.new(
        owner: owner,
        repository: repository,
        graph_changes: graph_changes,
      ).create_graph_update_job
    end

    sig do
      params(
        owner: HydroHandlers::GitHub::User,
        repository: HydroHandlers::GitHub::Repository
      ).returns(HydroHandlers::GitHub::User)
    end
    def setup_account_with_installation(owner:, repository:)
      installation_id = create_repository_install!(repository)

      # GitHub app installations are attached to the owner, so lets recreate
      # the owner data object with the new installation id.
      owner_with_install = HydroHandlers::GitHub::User.new(
        owner.attributes,
        installation_id:
      )

      owner_with_install.setup_account
      owner_with_install
    end

    sig { params(repository: HydroHandlers::GitHub::Repository).returns(Integer) }
    def create_repository_install!(repository) # rubocop:disable Metrics/MethodLength
      client = GitHub::Twirp::AppInstall.new(
        client: T.unsafe(Dependabot::Application).github_twirp_client,
        tenant: tenant_from(owner: repository.owner),
      )

      result = client.create_repository_install(repository_id: repository.id)

      Dependabot::Logger.info(
        msg: "Repository install requested",
        "gh.repo.id": repository.id,
        state: result.state,
        "gh.installation.id": result.installation_id
      )

      MetricsClient.increment(
        "update_job.on_demand_app_install",
        tags: {
          trigger: "dependency_graph",
          outcome: result.state || "unexpected",
        }
      )

      case result.state
      when :INSTALL_STATE_CREATED, :INSTALL_STATE_EXISTS
        if result.installation_id.blank? || result.installation_id.zero?
          raise InstallFailed, "Repository install succeeded but installation_id is blank or zero"
        end

        result.installation_id
      when :INSTALL_STATE_REFUSED_DELETED, :INSTALL_STATE_REFUSED_ARCHIVED, :INSTALL_STATE_REFUSED_SPAMMY
        raise InstallRefused, "Repository install refused with state: #{result.state}"
      else
        # If the install failed for an unknown reason, we should raise. This should not be retried.
        raise InstallFailed, "Repository install failed with state: #{result.state}"
      end
    end

    sig { params(owner: HydroHandlers::GitHub::User).returns(T.any(Tenant, NullTenant)) }
    def tenant_from(owner:)
      return NullTenant.new unless Dependabot.proxima?

      # Use the hydro information for the tenant as it may not exist in the database
      # if the account needs to be created.
      Tenant.new(
        github_id: owner.tenant_id.to_i,
        slug: owner.tenant_slug,
      )
    end

    sig { params(owner: HydroHandlers::GitHub::User).returns(T::Boolean) }
    def use_global_app_for_graph_jobs?(owner)
      T.unsafe(Dependabot::Application).monolith_feature_enabled?(
        feature: :dependabot_global_app_graph_jobs,
        actor: MonolithFeatureFlags::RawActor.new(FeatureFlags::Actor::User.new(owner.id)),
        use_cache: true,
      )
    end

    sig { params(owner: HydroHandlers::GitHub::User).void }
    def setup_account_with_global_app(owner)
      SetupAccountWithGlobalApp.new(
        github_id: owner.id,
        tenant_id: owner.tenant_id,
        tenant_slug: owner.tenant_slug,
        event_source: "job.update_graph_onboard_repository",
      ).run
    end
  end
end
