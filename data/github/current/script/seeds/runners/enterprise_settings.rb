# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class EnterpriseSettings < Seeds::Runner

      BIZ_NAME = "ReposSecurityBiz"

      sig { returns(String) }
      def self.help
        <<~HELP
        - Creates an enterprise with associated orgs and repos for policy testing
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        number_of_orgs = options[:orgs] || 10
        number_of_repos = options[:repos] || 20

        user = Seeds::Objects::User.monalisa
        bypasser_1 = nil

        if options[:bypass]
          bypasser_1 = Seeds::Objects::User.create(login: "bypasser1")
        end

        enable_features(options)
        fancy_puts "Enabled feature flags", :success

        fancy_puts "Creating business, orgs, and repos", :loading
        business = seed_business(user, options)
        fancy_puts "Orgs in #{business.name}:", :info, indent: 1
        (1..number_of_orgs).to_a.each do
          org = seed_org(user, business, options)
          team = seed_org_team(org, [bypasser_1], "Bypassers") if options[:bypass]
          (1..number_of_repos).to_a.each do
            repo = seed_repo(org, options)
            repo.add_team(team, action: :admin) if options[:bypass]
          end
          fancy_puts "#{org.display_login}", :success, indent: 2
        end

        fancy_puts "Created business, orgs, and repos", :success
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.enable_features(options = {})
        Seeds::Objects::FeatureFlag.toggle(action: "enable", feature_flag: :member_privilege_rulesets)
        Seeds::Objects::FeatureFlag.toggle(action: "enable", feature_flag: :member_privilege_rename)
        if options[:bypass]
          Seeds::Objects::FeatureFlag.toggle(action: "enable", feature_flag: :repo_policy_bypass)
        end
      end

      sig { params(user: User, options: T::Hash[Symbol, T.untyped]).returns(Business) }
      def self.seed_business(user, options = {})
        name = options[:name] || BIZ_NAME
        if options[:force]
          fancy_puts "Removing #{name}", :loading
          reset!(user, name)
          fancy_puts "Removed #{name}!", :success
        end
        existing_business = Business.find_by(name:)
        business = existing_business || Seeds::Objects::Business.create(owner: user, name:)
        seed_ruleset(business)
        business
      end

      sig { params(user: User, business: Business, options: T::Hash[Symbol, T.untyped]).returns(Organization) }
      def self.seed_org(user, business, options = {})
        login = unique_suffix(Faker::App.name)
        org = Seeds::Objects::Organization.create(admin: user, login:)
        business.add_organization(org)
        org.reload

        org
      end

      sig { params(org: Organization, members: [User], team_name: T.nilable(String)).returns(T.nilable(Team)) }
      def self.seed_org_team(org, members, team_name = Faker::Team.name)
        team_name = unique_suffix(team_name)
        members.each do |member|
          org.add_member(member)
        end
        create_team(org, team_name, members)
      end

      sig { params(owner: T.any(User, Organization), options: T::Hash[Symbol, T.untyped]).returns(Repository) }
      def self.seed_repo(owner, options = {})
        repo_name = unique_suffix(Faker::Creature::Animal.name)
        Seeds::Objects::Repository.create(
          repo_name:,
          owner_name: owner.display_login,
          setup_master: false,
          is_public: options[:is_public].nil? ? true : options[:is_public],
        )
      end

      sig do
        params(
          source: RuleEngine::Types::RuleSource,
          bypass_teams: T.nilable(T::Array[Team]),
          enforcement: T.nilable(Symbol),
        ).returns(RepositoryRuleset)
      end
      def self.seed_ruleset(source, bypass_teams: nil, enforcement: :enabled)
        existing_ruleset = source.rulesets.find_by(name: "Repos Security Policy")
        if existing_ruleset.present?
          fancy_puts "Removing existing ruleset", :loading, indent: 1
          existing_ruleset.delete
          fancy_puts "Removed existing ruleset", :success, indent: 1
        end

        ruleset = Seeds::Objects::Ruleset.create(name: "Repos Security Policy", source:, target: :repository, enforcement:, target_all: true)

        Seeds::Objects::Ruleset.add_bypass_actors(ruleset, bypass_teams.map { |team| {
            actor_id: team.id,
            actor_type: "Team",
            bypass_mode: nil,
          }
        }) if bypass_teams

        Seeds::Objects::Ruleset.add_bypass_actors(ruleset,
          [
            { actor_type: "OrganizationAdmin", bypass_mode: 0 },
            { actor_type: "DeployKey", bypass_mode: 0 }
          ])

        ruleset.upsert_rules([{
          rule_type: "repository_name",
          parameters: {
            negate: false,
            pattern: "security_.+",
          },
        }, {
          rule_type: "repository_delete",
          parameters: nil,
        }, {
          rule_type: "repository_visibility",
          parameters: {
            public: true,
            internal: false,
            private: false,
          },
        }])

        ruleset.save!

        ruleset
      end

      ### Utilities

      sig { params(org: Organization, name: String, members: T::Array[User]).returns(T.nilable(Team)) }
      def self.create_team(org, name, members)
        fancy_puts "Creating team", :loading, indent: 1
        team = Team.find_by(name:, organization: org)
        if team.nil?
          team = T.must(Seeds::Objects::Team.create!(
            name:,
            org:,
          ))
          fancy_puts "Created team", :success, indent: 1
        else
          fancy_puts "Team already exists", :info, indent: 1
        end
        fancy_puts "Adding members", :loading, indent: 1
        members.each do |user|
          team.add_member(user)
        end
        fancy_puts "Added members", :success, indent: 1
        team
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

      sig { params(value: String).returns(String) }
      def self.unique_suffix(value)
        name_wo_whitespace = value.gsub(/\s+/, "")
        return SecureRandom.hex(4) if name_wo_whitespace.empty?
        "#{name_wo_whitespace}-#{SecureRandom.hex(4)}"
      end

      sig { params(owner: User, name: String).void }
      def self.reset!(owner, name)
        business = Business.find_by(name:)
        return unless business

        if business
          business.organizations.each do |org|
            org.members.each do |member|
              org.remove_member(member) unless member == owner
            end
            org.repositories.each do |repo|
              repo.delete
            end
            org.delete
          end
          business.delete
        end
      end
    end
  end
end
