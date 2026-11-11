# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    # Populates the `github` org / `github/private-server` repo / `github-inc` business
    # with a varied cast of users, teams, and integrations so that the
    # "Restrict who can dismiss pull request reviews" (and any other) ruleset
    # actor pickers show a realistic selection at the repo, org, and enterprise
    # levels.
    #
    # What this seeds (idempotent; safe to re-run):
    #   * Enables FF `restrict_review_dismissals_rule` globally so the new rule
    #     shows up in the ruleset UI.
    #   * Adds ~6 users as members of the `github` org (and by extension, the
    #     `github-inc` business).
    #   * Creates 3 org teams with varied membership, including one nested
    #     child team.
    #   * Grants a couple of those teams access to `github/private-server`
    #     so they also show up in the repo-level picker.
    #   * Installs 2 GitHub Apps on the org so the "Integrations" actor type
    #     has entries to pick from.
    #
    # Intentionally NOT covered (add manually if needed):
    #   * Bypass actors on existing rulesets.
    #   * SSO / SAML enrollment. These actors will just show as regular users.
    #   * External collaborators (outside the org). The ruleset pickers
    #     typically scope to members, so we don't bother.
    class RestrictReviewDismissalsActors < Seeds::Runner
      ORG_LOGIN = "github"
      REPO_NAME = "private-server"

      USER_LOGINS = T.let(%w[
        rrd-reviewer-amy
        rrd-reviewer-bo
        rrd-reviewer-cai
        rrd-reviewer-dee
        rrd-reviewer-evan
        rrd-reviewer-fran
      ].freeze, T::Array[String])

      sig { returns(String) }
      def self.help
        <<~HELP
        - Populates `github` org and `github/private-server` repo with users, teams,
          and integrations so the ruleset actor pickers (e.g. Restrict Review
          Dismissals bypass / allowed actors) have variety at repo, org, and
          enterprise levels.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        Seeds::Objects::User.monalisa
        org = Organization.find_by(login: ORG_LOGIN)
        raise "Expected `#{ORG_LOGIN}` org to exist. Run the base seeds first." if org.nil?

        repo = Repository.find_by(owner_login: ORG_LOGIN, name: REPO_NAME)
        raise "Expected `#{ORG_LOGIN}/#{REPO_NAME}` repo to exist. Run the base seeds first." if repo.nil?

        fancy_puts "Enabling feature flag: restrict_review_dismissals_rule", :loading
        Seeds::Objects::FeatureFlag.enable(feature_flag: :restrict_review_dismissals_rule)
        fancy_puts "Feature flag enabled", :success

        fancy_puts "Creating reviewer users and adding them to #{ORG_LOGIN}", :loading
        users = USER_LOGINS.map { |login| Seeds::Objects::User.create(login:) }
        users.each { |u| org.add_member(u) }
        fancy_puts "Added #{users.size} users to org", :success

        fancy_puts "Creating teams in #{ORG_LOGIN}", :loading
        release_managers = find_or_create_team(org, name: "release-managers")
        add_members(release_managers, [users[0], users[1]].compact)

        security_reviewers = find_or_create_team(org, name: "security-reviewers")
        add_members(security_reviewers, [users[2], users[3]].compact)

        # Nested child team under security-reviewers. Shows in UI as
        # `security-reviewers/compliance`.
        compliance = find_or_create_team(org, name: "compliance", parent: security_reviewers)
        add_members(compliance, [users[4]].compact)

        # Grant teams repo access so they surface in repo-level pickers.
        grant_team_repo_access(release_managers, repo, action: :admin)
        grant_team_repo_access(security_reviewers, repo, action: :write)
        fancy_puts "Created #{[release_managers, security_reviewers, compliance].compact.size} teams", :success

        fancy_puts "Installing GitHub Apps on #{ORG_LOGIN}", :loading
        install_app(org:, name: "rrd-bot-guardrails")
        install_app(org:, name: "rrd-bot-automerge")
        fancy_puts "Installed apps", :success

        puts <<~MARKDOWN

          # Restrict Review Dismissals — actor seed complete

          Test URLs:
          * Repo:       http://github.localhost/#{ORG_LOGIN}/#{REPO_NAME}/settings/rules/new?target=branch
          * Org:        http://github.localhost/organizations/#{ORG_LOGIN}/settings/rules/new?target=branch
          * Enterprise: http://github.localhost/enterprises/#{T.must(org.business).slug}/rulesets/new?target=branch

          Users:  #{USER_LOGINS.join(", ")}
          Teams:  release-managers, security-reviewers, security-reviewers/compliance
          Apps:   rrd-bot-guardrails, rrd-bot-automerge
        MARKDOWN
      end

      sig { params(org: Organization, name: String, parent: T.nilable(Team)).returns(Team) }
      def self.find_or_create_team(org, name:, parent: nil)
        existing = Team.find_by(organization: org, name: name)
        return existing if existing

        team = T.must(Seeds::Objects::Team.create!(org:, name:, parent_team: parent))
        team
      end

      sig { params(team: Team, members: T::Array[User]).void }
      def self.add_members(team, members)
        members.each { |u| team.add_member(u) }
      end

      sig { params(team: Team, repo: Repository, action: Symbol).void }
      def self.grant_team_repo_access(team, repo, action:)
        return if team.repositories.exists?(id: repo.id)
        repo.add_team(team, action: action)
      end

      sig { params(org: Organization, name: String).void }
      def self.install_app(org:, name:)
        existing = ::Integration.find_by(slug: name.parameterize)
        if existing
          # Make sure it's installed on the target org.
          unless ::IntegrationInstallation.exists?(integration_id: existing.id, target_id: org.id, target_type: "Organization")
            Seeds::Objects::Integration.install(integration: existing, installer: org.admins.first, target: org, repo: [])
          end
          return
        end

        Seeds::Objects::Integration.create(
          owner: org,
          app_name: name,
          skip_restrict_names_with_github_validation: true,
        )
      end

      sig { params(message: String, type: Symbol, indent: T.nilable(Integer)).void }
      def self.fancy_puts(message, type, indent: 0)
        return unless Rails.env.development?
        indent_string = " " * (indent || 0) * 2
        icon = case type
        when :info then "ℹ️ "
        when :loading then "🌀"
        when :success then "✅"
        else ""
        end
        puts "#{indent_string}#{icon} #{message}"
      end
    end
  end
end
