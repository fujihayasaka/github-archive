# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to issue dependencies.
# Current existing issue dependencies are:
# - Blocked by

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("blocked_by.add") do |payload|
    source_repo, target_repo = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      [
        Repositories.domain.by_id(payload[:source_issue_repository_id]),
        Repositories.domain.by_id(payload[:target_issue_repository_id])
      ]
    else
      [
        Repository.find_by(id: payload[:source_issue_repository_id]),
        Repository.find_by(id: payload[:target_issue_repository_id])
      ]
    end

    message = {
      actor: Hydro::EntitySerializer.user(User.find_by(id: payload[:actor_id])),
      source_issue_repository: serializer.repository(source_repo),
      source_issue: Hydro::EntitySerializer.issue(payload[:source_issue]),
      target_issue_repository: serializer.repository(target_repo),
      target_issue: Hydro::EntitySerializer.issue(payload[:target_issue]),
      request_context: serializer.request_context(GitHub.context.to_hash),
    }

    publish(message, schema: "github.v1.BlockedByAdd")
  end

  subscribe("blocked_by.remove") do |payload|
    source_repo, target_repo = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      [
        Repositories.domain.by_id(payload[:source_issue_repository_id]),
        Repositories.domain.by_id(payload[:target_issue_repository_id])
      ]
    else
      [
        Repository.find_by(id: payload[:source_issue_repository_id]),
        Repository.find_by(id: payload[:target_issue_repository_id])
      ]
    end

    message = {
      actor: Hydro::EntitySerializer.user(User.find_by(id: payload[:actor_id])),
      source_issue_repository: serializer.repository(source_repo),
      source_issue: Hydro::EntitySerializer.issue(payload[:source_issue]),
      target_issue_repository: serializer.repository(target_repo),
      target_issue: Hydro::EntitySerializer.issue(payload[:target_issue]),
      request_context: serializer.request_context(GitHub.context.to_hash),
    }

    publish(message, schema: "github.v1.BlockedByRemove")
  end

  subscribe("issue_dependency.list.recalculate") do |payload|
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end

    message = {
      issue: Hydro::EntitySerializer.issue(payload[:issue]),
      repository: serializer.repository(repository),
      blocked_by: payload[:blocked_by],
      blocking: payload[:blocking],
      request_context: serializer.request_context(GitHub.context.to_hash),
    }

    publish(message, schema: "github.v1.IssueDependencyListRecalculate")
  end
end
