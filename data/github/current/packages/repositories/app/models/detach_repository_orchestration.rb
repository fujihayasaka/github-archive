# typed: false
# frozen_string_literal: true
class DetachRepositoryOrchestration < RepositoryOrchestration
  step :inspect_environment do
    return :skipped if repository.network.repositories.count + repository.network.deleted_repositories.count <= 1
    return :failed, "missing storage" unless repository.exists_on_disk? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return :failed, "not enough disk space available" unless repository.network.enough_space_to_extract?(repository, 1)
  end

  step :populate_orchestration do
    data[:old_network_id] = repository.network&.id
    data[:old_parent_id] = repository.parent&.id
    data[:was_root] = repository.network_root?
    data[:was_fork] = repository.fork?
  end

  job_start

  step :create_new_network do
    return if new_network.present?

    @new_network = if repository.network_root?
      old_network.create_parent(root: repository, parent: old_network.parent)
    else
      old_network.children.create(root: repository)
    end
    data[:new_network_id] = @new_network.id
  end

  step :copy_push_rules do
    # ignore validation errors, because our repo is still a fork at this point and cannot have push rules (yet)
    # We need the rules in place now, before it becomes the root to ensure push rules are always in effect
    RepositoryRuleset.copy_rules(old_network.root, repository, ["push"], validate: false)
  end

  step :move_files_on_disk do
    old_network.move_repositories_into_network([repository], new_network)
  end

  step :reparent_forks do
    old_network.reparent_forks!(repository)
    old_network.save!
  end

  step :update_repository_network do
    Repository.where(id: repository.id).update_all(["parent_id=?, source_id=?", nil, new_network.id])
    repository.reload
    repository.skip_search_index_sync = true
    repository.update_organization
  end

  step :sync_spokes_replica do
    repository.sync_routes_from_network
    repository.reload
  end

  step :async_copy_media do
    Media::Transition.async_copy(old_network, new_network)
  end

  step :reload_private_repos do
    repository.owner.owned_private_repositories.reload
  end

  step :touch_repo do
    repository.touch
  end

  step :calculate_network_counts do
    repository.calculate_network_counts!
    old_parent.reload.calculate_network_counts! if old_parent
  end

  step :audit_logs do
    name = Audit.context[:from]&.start_with?("stafftools") ? "staff.repo_detach" : "repo.detach"
    GitHub.instrument name, repo: repository, old_network_id: old_network&.id
  end

  step :reindex_network do
    repository.reindex_after_network_operation(data[:was_root], data[:was_fork], old_network)
  end

  step :publish_detached do
    message = build_hydro_event_message.merge({
      old_network_id: data[:old_network_id],
      old_parent_id: data[:old_parent_id],
      was_root: data[:was_root],
      was_fork: data[:was_fork]
    })
    publish_hydro_event(schema: "github.repositories.v1.Detached", message:)
  end

  def new_network_id
    data[:new_network_id]
  end

  def new_network
    @new_network ||= RepositoryNetwork.find_by_id(new_network_id) if new_network_id
  end

  def old_network
    @old_network ||= RepositoryNetwork.find_by_id(data[:old_network_id])
  end

  def old_parent
    @old_parent ||= Repository.find_by_id(data[:old_parent_id])
  end
end
