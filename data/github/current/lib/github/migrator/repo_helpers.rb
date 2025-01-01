# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    module RepoHelpers
      def local_repo?(repo)
        GitHub::DGit.local_access? repo.host
      end
    end
  end
end
