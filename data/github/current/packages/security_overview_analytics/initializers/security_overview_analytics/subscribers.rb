# typed: strict
# frozen_string_literal: true

# Until and unless there is a hydro topic (with or without repository orchestration) for this, we'll have to be notified via pubsub.
GitHub.subscribe "repo.update_default_branch" do |_name, _start, _ending, _transaction_id, payload|
  repo_id, org_id = payload.values_at(:repo_id, :org_id)
  ::SecurityOverviewAnalytics::RepositoryDefaultBranchChangedJob.perform_later(repository_id: repo_id)
end
