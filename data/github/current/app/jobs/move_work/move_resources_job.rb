# typed: true
# frozen_string_literal: true

class MoveWork::MoveResourcesJob < ApplicationJob
  extend T::Sig

  queue_as :move_work

  retry_on ActiveJob::DeserializationError
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(move_work: MoveWork).void }
  def perform(move_work)
    move_work.move_work_items.repositories.find_each do |move_work_item|
      transfer_repo(move_work_item.resource, T.must(move_work.target), T.must(move_work.user))
    end

    move_work.move_work_items.projects.find_each do |move_work_item|
      transfer_project(move_work_item.resource, T.must(move_work.target), T.must(move_work.user))
    end

    with_write { move_work.complete! }
  end

  private

  sig { params(repo: Repository, target: User, actor: User).void }
  def transfer_repo(repo, target, actor)
    # Transferring repos generates a lot of ability grants which can cause replication delay.
    # Ability::Grant throttles on Mysql1 so let's wait until that is in a good state before beginning the transfer.
    Ability.throttle do
      rename_repo_if_name_already_exists_on_target(repo, target, actor)
      if with_write { repo.transfer_ownership_to(target, actor: actor) }
        GitHub.dogstats.increment("move_work.move_resources_job", tags: [
          "resource_type:repository",
          "result:success",
        ])
      else
        GitHub.dogstats.increment("move_work.move_resources_job", tags: [
          "resource_type:repository",
          "result:warning",
        ])
      end
    end
  rescue Repository::TransferDependency::TransferFailedError => e
    GitHub.logger.error("repository transfer failed",
      exception: e,
      "gh.repo.id": repo.id,
      "code.namespace": "MoveWork::MoveResourcesJob",
      "code.function": "transfer_repo"
    )

    GitHub.dogstats.increment("move_work.move_resources_job", tags: [
      "resource_type:repository",
      "result:failure",
    ])
  end

  sig { params(repo: Repository, target: User, actor: User).void }
  def rename_repo_if_name_already_exists_on_target(repo, target, actor)
    if target.find_repo_by_name(repo.name)
      new_name = "#{repo.name}-#{SecureRandom.hex(4)}"
      with_write { repo.rename(new_name, actor: actor) }
    end
  end

  sig { params(project: Project, target: User, actor: User).void }
  def transfer_project(project, target, actor)
    result = with_write { project.change_owner!(new_owner: target) }

    GitHub.dogstats.increment("move_work.move_resources_job", tags: [
      "resource_type:project",
      "result:#{result ? "success" : "failure"}",
    ])
  end
end
