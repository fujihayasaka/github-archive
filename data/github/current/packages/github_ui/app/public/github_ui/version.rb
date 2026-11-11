# typed: strict
# frozen_string_literal: true

require "progeny"

module GitHubUI
  module Version
    ROOT_DIR = T.let(GitHub::AppEnvironment.root.join("../github-ui/").to_s.freeze, String)

    # Based on GitHub::Version#spawn_git_in_rails_root
    sig { returns(String) }
    def self.current_branch
      env = Hash.new
      ENV.each_key do |k|
        env[k] = nil if k.start_with? "GIT_"
      end

      Progeny::Command.new(env, "git", "-C", ROOT_DIR, "branch", "--show-current").out.presence || "unknown"
    end

    sig { returns(SHA) }
    def self.current_sha
      GitHubUI::Manifest.new.git_sha
    end

    @current_ref = T.let(nil, T.nilable(SHA))
    # The branch name if in development, otherwise the current SHA
    sig { returns(T.any(String, SHA)) }
    def self.current_ref
      return current_branch if GitHub.ui_dev_server_enabled?

      current_sha
    end
  end
end
