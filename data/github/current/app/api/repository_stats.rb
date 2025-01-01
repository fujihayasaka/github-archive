# typed: true
# frozen_string_literal: true

class Api::RepositoryStats < Api::App
  # Get a list of contributors with weekly additions, deletions and commit counts
  get "/repositories/:repository_id/stats/contributors", operation_id: "repos/get-contributors-stats" do
    repo = find_repo!

    control_access :get_repo_stats,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    halt 204 if repo.empty?

    graph_data = begin
                   GitHub::RepoGraph.contributors_data(repo, viewer: current_user, cache_only: robot?)
                 rescue GitHub::RepoGraph::UnusableDataError, GitHub::RepoGraph::InvalidRepoError
                   halt 204
                 end

    if graph_data.nil?
      deliver_empty status: 202
    else
      deliver :contributor_totals_hash, graph_data
    end
  end

  # Get the last year of commit activity data
  get "/repositories/:repository_id/stats/commit_activity", operation_id: "repos/get-commit-activity-stats" do
    repo = find_repo!

    control_access :get_repo_stats,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    halt 204 if repo.empty?

    graph_data = begin
                   GitHub::RepoGraph.commit_activity_data(repo, viewer: current_user, cache_only: robot?)
                 rescue GitHub::RepoGraph::UnusableDataError
                   halt 204
                 end

    if graph_data.nil?
      deliver_empty status: 202
    else
      deliver_raw graph_data
    end
  end

  # Get the number of additions and deletions per week
  get "/repositories/:repository_id/stats/code_frequency", operation_id: "repos/get-code-frequency-stats" do
    halt 403 if logged_in? && current_user.spammy?
    repo = find_repo!

    control_access :get_repo_stats,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    halt 204 if repo.empty?
    error_for_large_repo_if_eventer_disabled(repo)

    graph_data = begin
                   GitHub::RepoGraph.code_frequency_data(repo, viewer: current_user, cache_only: robot?)
                 rescue GitHub::RepoGraph::UnusableDataError
                   halt 204
                 end

    if graph_data.nil?
      deliver_empty status: 202
    else
      deliver_raw graph_data
    end
  end

  # Get the number of commits per hour in day
  get "/repositories/:repository_id/stats/punch_card", operation_id: "repos/get-punch-card-stats" do
    repo = find_repo!

    control_access :get_repo_stats,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    halt 204 if repo.empty?

    graph_data = begin
                   GitHub::RepoGraph.punch_card_data(repo)
                 rescue GitHub::RepoGraph::UnusableDataError
                   halt 204
                 end
    if graph_data.nil?
      deliver_empty status: 202
    else
      deliver_raw graph_data
    end
  end

  # Get the weekly commit count for both the repo owner and everyone else
  get "/repositories/:repository_id/stats/participation", operation_id: "repos/get-participation-stats" do
    repo = find_repo!
    control_access :get_repo_stats,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if repo.empty?
      # Ugh.  Don't break the Windows app.
      deliver_raw all: [], owner: []
    else
      graph_data = begin
                     GitHub::RepoGraph.participation_data(repo)
                   rescue GitHub::RepoGraph::UnusableDataError
                     halt 204
                   end

      if graph_data.nil?
        deliver_empty status: 202
      else
        deliver_raw graph_data
      end
    end
  end

  def error_for_large_repo_if_eventer_disabled(repo)
    if !GitHub.enterprise?
      error_threshold = 10_000
      commit_count = repo.rpc.fast_commit_count(repo.default_oid, error_threshold, timeout: 2)
      deliver_error! 422, message: "repository must have fewer than #{error_threshold} commits" if commit_count >= error_threshold
    end
  end
end
