# typed: false
# frozen_string_literal: true

module Orgs::TeamDiscussions::TransferControllerMethods
  include GitHub::Memoizer

  DEFAULT_MAX_RESULTS = 100

  private

  def ensure_discussions_available
    render_404 unless GitHub.discussions_available_on_platform?
  end

  memoize def candidate_repositories
    repos = this_organization.visible_repositories_for(current_user).limit(DEFAULT_MAX_RESULTS)
    max_category_repo_filter(authzd_repo_filter(repos))
  end

  def authzd_repo_filter(repos)
    requests = repos.map do |repo|
      {
        action: :transfer_team_discussion_to_discussions,
        actor: current_user,
        subject: repo,
        context: {
          current_team_id: this_team.id,
          current_team_organization_id: this_team.organization_id
        }
      }
    end

    authorized_repos = []
    requests.each_slice(DEFAULT_MAX_RESULTS) do |request_batch|
      responses = ::Permissions::Enforcer.batch_authorize(requests: request_batch)
      request_batch.each do |request|
        if responses[request].allow?
          authorized_repos.append(request[:subject])
        end
      end
    end
    authorized_repos
  end

  def max_category_repo_filter(repos)
    repos.reject { |repo| repo.has_max_categories? }
  end
end
