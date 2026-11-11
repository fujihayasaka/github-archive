# typed: true
# frozen_string_literal: true

module GitHub
  class DGit
    class RepoType
      # Values for the repository_type field.
      REPO = 0
      WIKI = 1
      GIST = 2
      # Value for getting networks from spokesd.
      NETWORK = 3

      # Convenience array for selecting and deleting types that join
      # against the `repositories` table.
      REPO_ISH = [REPO, WIKI].freeze

      # A map for showing human-readable names of RepoType values.
      REPO_TYPES = {
        REPO => "repo",
        WIKI => "wiki",
        GIST => "gist",
        NETWORK => "network",
      }
    end
  end
end
