# typed: strict
# frozen_string_literal: true

# Hydro event subscriptions related to Conduit (feed and events api).
Hydro::EventForwarder.configure(source: GitHub) do
  subscribe("wiki.push") do |payload|
    actor_id, repo_id, updates = payload.values_at(:actor_id, :repo_id, :updates)
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(repo_id)
    else
      Repository.find_by(id: repo_id)
    end
    user = User.find_by(id: actor_id)

    next unless repository && user

    message = {
      actor: serializer.user(user),
      repository: serializer.repository(repository),
      repository_owner: serializer.user(repository.owner),
      updates: updates.map do |update|
        {
          action: update[:action],
          name: update[:page_name],
          sha: update[:sha],
        }
      end
    }

    publish(message, schema: "github.v1.WikiPush")
  end
end
