# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module GitSrcMigrator
      def git_src_migrator_github_app_slug
        "git-src-migrator"
      end

      def git_src_migrator_github_app_name
        "git-src-migrator"
      end
    end
  end

  extend Config::GitSrcMigrator
end
