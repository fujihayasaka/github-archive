# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    module ReposSecurityBase
      extend T::Helpers

      requires_ancestor { Seeds::Runner }

      Options = T.type_alias { T::Hash[Symbol, T.untyped] }

      sig { params(options: Options).void }
      def run(options = {})
        enable_features
        initialize_repo(options)
      end

      sig { params(options: Options).void }
      def initialize_repo(options = {})
        if options[:force]
          fancy_puts "Deleting existing #{repo_name} repo", :loading, indent: 1
          Repository.find_by(name: repo_name)&.destroy!
          fancy_puts "Deleted existing #{repo_name} repo", :success, indent: 1
          fancy_puts "Deleting existing #{org_name} org", :loading, indent: 1
          Organization.find_by(login: org_name)&.destroy!
          ReservedLogin.untombstone!(org_name)
          fancy_puts "Deleted existing #{org_name} org", :success, indent: 1
        end

        repos_security_org = Organization.find_by(login: org_name)
        if repos_security_org.nil?
          fancy_puts "Creating organization: #{org_name}", :loading, indent: 1
          repos_security_org = Seeds::Objects::Organization.create(login: org_name, admin: user)
          fancy_puts "Created organization: #{org_name}", :success, indent: 1
        else
          fancy_puts "Organization #{repos_security_org.login} already exists", :info, indent: 1
        end

        repo = create_repo_if_not_exists(name: repo_name, owner: repos_security_org, is_public: true)

        seed_repo(repo, repos_security_org, options = {})
      end

      sig { params(owner: T.any(User, Organization), name: String, is_public: T.nilable(T::Boolean)).returns(Repository) }
      def create_repo_if_not_exists(owner:, name:, is_public: true)
        fancy_puts "Creating repository", :loading, indent: 1
        repo = Repository.find_by(owner_login: owner.login, name:)
        if repo.nil?
          repo = Seeds::Objects::Repository.create(
            repo_name: name,
            owner_name: owner.login,
            setup_master: true,
            is_public:,
          )
          fancy_puts "Created repository", :success, indent: 1
        else
          fancy_puts "Repository already exists", :info, indent: 1
        end
        repo
      end

      sig { params(message: String, type: Symbol, indent: T.nilable(Integer)).void }
      def fancy_puts(message, type, indent: 0)
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
      def random_string(length)
        # sorbet doesn't like passing args to to_s 🤷🏼
        r = T.unsafe(rand(36**length))
        r.to_s(36)
      end

      sig { void }
      def enable_features
        if feature_flags.any?
          fancy_puts "Enabling feature flags...", :loading
          feature_flags.each do |feature_flag|
            fancy_puts feature_flag.to_s, :info, indent: 1
            Seeds::Objects::FeatureFlag.enable(feature_flag:)
          end
          fancy_puts "Enabled feature flags", :success
        end
      end

      abstract!

      sig { overridable.returns(String) }
      protected def org_name
        "#{Faker::Lorem.word}-#{random_string(4)}"
      end

      sig { overridable.returns(String) }
      protected def repo_name
        "#{Faker::Lorem.word}-#{random_string(4)}"
      end

      sig { overridable.returns(T::Array[Symbol]) }
      protected def feature_flags
        []
      end

      sig { abstract.params(repo: Repository, org: Organization, options: Options).void }
      protected def seed_repo(repo, org, options); end

      sig { overridable.returns(User) }
      def user
        Seeds::Objects::User.monalisa
      end
    end
  end
end
