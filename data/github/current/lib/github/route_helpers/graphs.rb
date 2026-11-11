# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_repo_graphs_path(repo)
      expand_nwo_from :repo_graphs_path, repo
    end

    def gh_commit_activity_path(repo)
      expand_nwo_from :commit_activity_path, repo
    end

    def gh_code_frequency_path(repo)
      expand_nwo_from :code_frequency_path, repo
    end

    def gh_contributors_graph_path(repo)
      expand_nwo_from :contributors_graph_path, repo
    end

    def gh_punch_card_path(repo)
      expand_nwo_from :punch_card_path, repo
    end

    def gh_traffic_path(repo)
      expand_nwo_from :traffic_path, repo
    end

    def gh_community_graph_path(repo, period = nil)
      community_graph_path(repo.owner_display_login, repo, period: period)
    end
  end
end
