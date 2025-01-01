# typed: false
# frozen_string_literal: true

require "progeny"

module GitHub
  module Version
    def spawn_git_in_rails_root(*args)
      # Run the command with all Git-related environment variables
      # unset, so that one of them (e.g. GIT_DIR) doesn't cause Git to
      # refer to a different repository. Note that the correct way to
      # do this is to run "git rev-parse --local-env-vars" to get the
      # list of variables to clear. But this cheaper method is good
      # enough for the simple commands we need to run here.
      env = Hash.new
      ENV.each_key do |k|
        env[k] = nil if k.start_with? "GIT_"
      end
      Progeny::Command.new(env, "git", "-C", GitHub::AppEnvironment.root.to_s, *args)
    end
    private :spawn_git_in_rails_root

    # The SHA1 of the commit that was HEAD when the process started. This is
    # used in production to determine which version of the app is deployed.
    #
    # Returns the 40 char commit SHA1 string.
    def current_sha
      @current_sha ||=
        if File.readable?(path = "#{GitHub::AppEnvironment.root}/SHA1")
          File.read(path).strip
        else
          sha = spawn_git_in_rails_root("rev-parse", "HEAD").out.strip
          sha.empty? ? "unknown" : sha
        end.freeze
    end
    attr_writer :current_sha

    # The ref name of the commit that was HEAD when the process started. This is
    # used in production to determine which version of the app is deployed.
    #
    # Returns the ref name
    def current_ref
      @current_ref ||=
        if GitHub.enterprise?
          installed_version
        elsif (sha = current_sha) && (sha == "unknown" || sha.blank?)
          "unknown"
        elsif File.exist?("#{GitHub::AppEnvironment.root}/BRANCH_NAME") &&
              (branch_name = File.read("#{GitHub::AppEnvironment.root}/BRANCH_NAME").chomp.presence)
          branch_name
        elsif Dir.exist?("#{GitHub::AppEnvironment.root}/.git")
          if File.exist?("#{GitHub::AppEnvironment.root}/.git/DEPLOY_HEAD") &&
              (deploy_head = File.read("#{GitHub::AppEnvironment.root}/.git/DEPLOY_HEAD").chomp.presence)
            deploy_head.sub(%r{\A(refs/)?remotes/[^/]+/}, "")
          elsif File.exist?("#{GitHub::AppEnvironment.root}/.git/HEAD") && File.read("#{GitHub::AppEnvironment.root}/.git/HEAD") =~ %r{ref: refs/heads/(.*)}
            $1
          else
            spawn_git_in_rails_root("name-rev", "--name-only", sha).out.presence || "unknown"
          end
        else
          "unknown"
        end.freeze
    end
    attr_writer :current_ref

    # Returns the currently installed GitHub Enterprise version
    # like "Version 2.23" when known, otherwise "Version unknown".
    #
    # Returns String.
    def installed_version
      @installed_version ||= "Version #{version_number}"
    end
    attr_writer :installed_version

    # The major and minor number of the current enterprise string.
    #
    # Returns a string like 2.1, or the original version_number string if it is not in semver notation.
    def major_minor_version_number
      version_number.split(".").slice(0, 2).join(".")
    end

    def version_number
      ENV["ENTERPRISE_INSTALLED_VERSION"] || ENV["INSTALLED_VERSION"] || "unknown"
    end

    # The ref + SHA1 of the commit that was HEAD when the process started. This is
    # used in production to determine which version of the app is deployed.
    #
    # Returns the ref name + shortened SHA1
    def current_head
      @current_head ||=
        if (sha = current_sha) == "unknown"
          "unknown"
        else
          "(#{current_ref} [#{sha[0, 7]}])"
        end
    end
    attr_writer :current_head

  end
end
