# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class Eventer
      autoload :CodeFrequency, "github/repo_graph/eventer/code_frequency"
      autoload :CommitActivity, "github/repo_graph/eventer/commit_activity"
      autoload :Contributors, "github/repo_graph/eventer/contributors"

      ADDITIONS = "RepoGraphs_Additions"
      DELETIONS = "RepoGraphs_Deletions"
      COMMITS = "RepoGraphs_Commits"
      INDEXED = "RepoGraphs_Indexed"

      CONTRIBUTOR_DATA_EVENTS = [
        ADDITIONS,
        DELETIONS,
        COMMITS,
      ].freeze

      CODE_FREQUENCY_EVENTS = [
        ADDITIONS,
        DELETIONS,
      ].freeze
    end
  end
end
