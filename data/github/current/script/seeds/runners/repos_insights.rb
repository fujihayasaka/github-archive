# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class ReposInsights < Seeds::Runner
      REPOS_SECURITY_ORG = "repos-security"
      REPO_NAME = "insights"

      sig { returns(String) }
      def self.help
        <<~HELP
        - Seeds a pre-made repo with lots of historical commits for testing purposes.
        Use `-f` (force) flag to recreate org and repos from scratch.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        user = Seeds::Objects::User.monalisa
        repos_contributor_1 = Seeds::Objects::User.create(login: "reposcontributor1")
        repos_contributor_2 = Seeds::Objects::User.create(login: "reposcontributor2")

        fancy_puts "Enabling feature flags", :loading
        enable_features
        fancy_puts "Enabled feature flags", :success

        fancy_puts "Creating orgs, repos, and commits", :loading
        seed_repo(user, [repos_contributor_1, repos_contributor_2], options)
        fancy_puts "Created orgs, repos, and commits", :success
      end

      sig { params(user: User, collaborators: [User, User], options: T::Hash[Symbol, T.untyped]).void }
      def self.seed_repo(user, collaborators, options = {})
        if options[:force]
          fancy_puts "Deleting existing #{REPO_NAME} repo", :loading, indent: 1
          Repository.find_by(name: REPO_NAME)&.destroy!
          fancy_puts "Deleted existing #{REPO_NAME} repo", :success, indent: 1
          fancy_puts "Deleting existing #{REPOS_SECURITY_ORG} org", :loading, indent: 1
          Organization.find_by(login: REPOS_SECURITY_ORG)&.destroy!
          ReservedLogin.untombstone!(REPOS_SECURITY_ORG)
          fancy_puts "Deleted existing #{REPOS_SECURITY_ORG} org", :success, indent: 1
        end

        repos_security_org = Organization.find_by(login: REPOS_SECURITY_ORG)
        if repos_security_org.nil?
          fancy_puts "Creating organization: #{REPOS_SECURITY_ORG}", :loading, indent: 1
          repos_security_org = Seeds::Objects::Organization.create(login: REPOS_SECURITY_ORG, admin: user)
          fancy_puts "Created organization: #{REPOS_SECURITY_ORG}", :success, indent: 1
        else
          fancy_puts "Organization #{repos_security_org.login} already exists", :info, indent: 1
        end

        repo = create_repo_if_not_exists(name: REPO_NAME, owner: repos_security_org, is_public: true)

        repos_security_org.add_member(collaborators[0])

        repos_security_org.add_member(collaborators[1])

        fancy_puts "Creating commits", :loading, indent: 1

        fancy_puts "for #{user.display_login}", :info, indent: 2
        create_commit_history(committer: user, repo:, from: 6.months.ago, to: 3.months.ago)
        fancy_puts "for #{collaborators[0].display_login}", :info, indent: 2
        create_commit_history(committer: collaborators[0], repo:, from: 5.months.ago, to: 2.months.ago)
        fancy_puts "for #{collaborators[1].display_login}", :info, indent: 2
        create_commit_history(committer: collaborators[1], repo:, from: 3.months.ago)

        fancy_puts "Created commits", :success, indent: 1
      end

      sig { params(committer: User, repo: Repository, branch: T.nilable(String), from: T.nilable(Time), to: T.nilable(Time)).void }
      def self.create_commit_history(committer:, repo:, branch: nil, from: 3.months.ago, to: Time.now)
        from = T.cast(from, Time).to_date
        to = T.cast(to, Time).to_date

        (from..to).each { |date| Seeds::Objects::Commit.create(
            committer:,
            repo:,
            branch_name: branch || repo.default_branch,
            files: {
              "dummy-file.txt" => random_string(63)
            },
            message: "create a dummy file",
            date: date.to_time.iso8601,
          ) unless rand(3) == 1
        }
      end

      sig { params(owner: T.any(User, Organization), name: String, is_public: T.nilable(T::Boolean)).returns(Repository) }
      def self.create_repo_if_not_exists(owner:, name:, is_public: true)
        fancy_puts "Creating repository", :loading, indent: 1
        repo = Repository.find_by(owner_login: owner.login, name: name)
        if repo.nil?
          repo = Seeds::Objects::Repository.create(
            repo_name: name,
            owner_name: owner.login,
            setup_master: true,
            is_public: is_public
          )
          fancy_puts "Created repository", :success, indent: 1
        else
          fancy_puts "Repository already exists", :info, indent: 1
        end
        repo
      end

      sig { params(message: String, type: Symbol, indent: T.nilable(Integer)).void }
      def self.fancy_puts(message, type, indent: 0)
        return unless Rails.env.development?
        indent_string = " " * (indent || 0) * 2
        icon = case type
        when :info
          "ℹ️ "
        when :loading
          "🌀"
        when :success
          "✅"
        else
          ""
        end
        puts "#{indent_string}#{icon} #{message}"
      end

      sig { params(length: Integer).returns(String) }
      def self.random_string(length)
        # sorbet doesn't like passing args to to_s 🤷🏼
        r = T.unsafe(rand(36**length))
        r.to_s(36)
      end

      sig { void }
      def self.enable_features
        features = []

        if features.any?
          fancy_puts "Enabling feature flags...", :loading
          features.each do |feature|
            Seeds::Objects::FeatureFlag.enable(feature_flag: feature, actor: User.find_by_login("monalisa"))
          end
          fancy_puts "Enabled feature flags", :success
        end
      end
    end
  end
end
