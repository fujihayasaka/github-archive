# typed: strict
# frozen_string_literal: true

# Hydro event subscriptions related to Conduit (feed and events api).
Hydro::EventForwarder.configure(source: GitHub) do
  subscribe("wiki.push") do |payload|
    actor_id, repo_id, updates = payload.values_at(:actor_id, :repo_id, :updates)
    repository = Repository.find_by(id: repo_id)
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
