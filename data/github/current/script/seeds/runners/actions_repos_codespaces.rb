# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class ActionsReposCodespaces < Seeds::Runner
      CLONE_URL_TEMPLATE = "https://github.com/%s/%s.git"

      ACTIONS_ORGS_AND_REPOS = {
        actions: %w[checkout cache download-artifact upload-artifact starter-workflows],
        ruby: %w[setup-ruby]
      }

      def self.help
        <<~HELP
        Copies over a small, core set of repositories from the actions org (and others) as a default for Codespaces
        HELP
      end

      class << self
        def run(options = {})
          Seeds::Objects::User.two_factor_enable!(user: Seeds::Objects::User.monalisa)

          ACTIONS_ORGS_AND_REPOS.each do |org_name, repos|
            org = Seeds::Objects::Organization.create(login: org_name, admin: Seeds::Objects::User.monalisa)

            Dir.mktmpdir do |dir|
              Dir.chdir(dir) do
                repos.each do |a|
                  puts "=" * 30
                  copy_repo(org.login, a)
                end
              end
            end
          end
        end

        private

        # Wrapping this makes it easy to test
        def run_cmd(cmd)
          system(cmd)
        end

        def copy_repo(owner_name, repo_name)
          clone_url = CLONE_URL_TEMPLATE % [owner_name, repo_name]
          puts "Cloning Repo #{clone_url}"

          puts "Creating directory #{repo_name}"
          FileUtils.mkdir(repo_name) # Make sure the path isnt empty, useful for tests
          puts "Git clone"
          run_cmd("git clone -q #{clone_url} #{repo_name}")
          action_dir = Pathname.new(repo_name).join(".git")

          puts "Pushing to local"
          # We're only pulling the public repos, so these should be public too
          if Rails.env.test?
            nwo = "#{owner_name}/#{repo_name}"
            repo = Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: false, is_public: true)
          else
            repo = Seeds::Objects::Repository.restore_premade_repo(location_premade_git: action_dir.realpath.to_s, owner_name: owner_name, repo_name: repo_name, is_public: true)
          end
        end
      end
    end
  end
end
