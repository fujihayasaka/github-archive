# typed: strict
# frozen_string_literal: true

class BusinessOrchestrationNotifyRepositoryAccessChangedJob < ApplicationJob
  queue_as :business_orchestration_notify_repository_access_changed
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  READ_REPO_BATCH_SIZE = 1000
  LOCK_TTL = T.let(5.minutes, Integer)
  GLOBAL_LOCK_KEY = T.let("business_orchestration_notify_repository_access_changed", String)

  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  around_perform do |_job, block|
    GitHub::Restraint.new.lock!(GLOBAL_LOCK_KEY, GitHub.business_orchestration_notify_repository_access_changed_job_limit, LOCK_TTL) do
      block.call
    end
  end

  sig { params(orchestration: RemoveOrganizationMembersCleanupBusinessOrchestration, user_ids: T::Array[Integer]).void }
  def perform(orchestration, user_ids)
    GitHub.logger.info("BusinessOrchestrationNotifyRepositoryAccessChangedJob started", {
      "gh.business.id": T.must(orchestration.business).id,
      "gh.business.orchestration.id": orchestration.id,
      "gh.user.ids": user_ids,
    })

    users = User.where(id: user_ids)
    return if users.empty?

    all_orgs_private_repo_ids = Repository.where(organization_id: orchestration.organization_ids).private_scope.pluck(:id)

    users.each do |user|
      return if T.must(orchestration.business).kill_switch_enabled?("BusinessOrchestrationNotifyRepositoryAccessChangedJob", feature_flag: :enterprise_teams_killswitch, log_fields: {
        "gh.business.id": T.must(orchestration.business).id,
        "gh.business.orchestration.id": orchestration.id
      })

      repo_ids = all_orgs_private_repo_ids - repo_ids_visible_to_user(user, all_orgs_private_repo_ids)

      if repo_ids.any?
        GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
          user: user,
          repository_ids: repo_ids,
        })
        GitHub.logger.info("BusinessOrchestrationNotifyRepositoryAccessChangedJob triggered event", {
          "gh.business.id": T.must(orchestration.business).id,
          "gh.business.orchestration.id": orchestration.id,
          "gh.user.id": user.id,
          "gh.repositories.count": repo_ids.size,
        })
      end
    end

    GitHub.logger.info("BusinessOrchestrationNotifyRepositoryAccessChangedJob finished", {
      "gh.business.id": T.must(orchestration.business).id,
      "gh.business.orchestration.id": orchestration.id,
      "gh.user.ids": user_ids,
    })
  end

  private

  sig { params(user: User, repo_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def repo_ids_visible_to_user(user, repo_ids)
    associated_repository_ids = []
    repo_ids.each_slice(READ_REPO_BATCH_SIZE).map do |group_ids|
      Repository.throttle do
        associated_ids = user.associated_repository_ids(repository_ids: group_ids)
        associated_repository_ids.concat(associated_ids).uniq!
      end
    end

    # Load all internal repositories for the user. This is only to exclude internal repos from being considered
    # accessible, so it doesn't matter if we load Rando Business internal IDs.
    associated_repository_ids |= user.internal_repositories.pluck(:id)
    associated_repository_ids
  end
end
