# typed: strict
# frozen_string_literal: true

# Until and unless there is a hydro topic (with or without repository orchestration) for this, we'll have to be notified via pubsub.
GitHub.subscribe "repo.update_default_branch" do |_name, _start, _ending, _transaction_id, payload|
  repo_id, org_id = payload.values_at(:repo_id, :org_id)
  ::SecurityOverviewAnalytics::RepositoryDefaultBranchChangedJob.perform_later(repository_id: repo_id)
end

# Changes in enablement for Auto CodeQL aka Default Setup
# See also packages/security_products/app/models/code_scanning/auto_codeql.rb
GitHub.subscribe /\Arepo.codeql_(enabled|updated|disabled)\Z/ do |name, _start, _ending, _transaction_id, payload|
  repository_id = payload.dig(:repo_id)
  ::SecurityOverviewAnalytics::CodeScanningAutoCodeqlFeatureToggledJob.perform_later(repository_id:, source_event: name)
end
