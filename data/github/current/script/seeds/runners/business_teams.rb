# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class BusinessTeams < Seeds::Runner
      FEATURE_FLAGS = %w(
        business_teams
        enterprise_teams_org_roles
        check_business_team_in_associated_repository_ids
        business_team_path
      )

      def self.help
        <<~HELP
        Enables business teams for the default GitHub, Inc enterprise for local development
        Adds:
        - business teams
        - member users
        - organization assocations
        - repository assignments
        - org role assignments

        To run the seed script:
          1. script/server
          2. bin/seed business_teams
        HELP
      end

      # Custom Org Roles to create
      CUSTOM_ORG_ROLES = 3
      # @TODO Repository Roles to create
      CUSTOM_REPO_ROLES = 0
      # Base Business Teams to create
      BASE_BUSINESS_TEAMS = 3
      # Users to be created as business team members
      MEMBER_USERS = 10
      # Organizations to create and associate with the business
      BUSINESS_ORGS = 2
      # Repositories to create and assign to orgs
      ORG_REPOS = 2


      def self.run(options = {})
        FEATURE_FLAGS.each do |flag|
          Seeds::Objects::FeatureFlag.toggle(action: "enable", feature_flag: flag)
        end

        biz = Seeds::Objects::Business.github
        mona = Seeds::Objects::User.monalisa
        gh_org = Seeds::Objects::Organization.github(admin: mona)

        bt_all_orgs = BusinessTeam.find_or_create_by!(name: "all_orgs-bt", business: biz, organization_selection_type: :all)
        bt_no_orgs = BusinessTeam.find_or_create_by!(name: "org_select_disabled-bt", business: biz, organization_selection_type: :disabled)
        bt_select = BusinessTeam.find_or_create_by!(name: "select_orgs-bt", business: biz, organization_selection_type: :selected)
        biz_teams = [bt_all_orgs, bt_no_orgs, bt_select]
        puts "Created business teams"

        org_system_roles = ::OrganizationRole.visible_preset_roles(gh_org).take(5)
        org_system_roles.each do |role|
          biz_team = BusinessTeam.find_or_create_by!(name: "#{role.name}-bt", business: biz, organization_selection_type: :all)
          unless gh_org.nil? || biz_team.nil?
            gh_org.grant_org_role(assignee: biz_team, role: role)
            puts "Granted system org role #{role.name} to #{biz_team.name} for #{gh_org.name}."
            biz_teams << biz_team
          end
        end

        business_orgs = []
        org_repos = []
        BUSINESS_ORGS.times do |org_num|
          org = Seeds::Objects::Organization.create(login: "biz-org-#{org_num + 1}", admin: mona)
          org_repo = Seeds::Objects::Repository.create(owner_name: org.login, repo_name: "biz-org-#{org_num + 1}-repo", setup_master: true, is_public: false)
          org.add_member(mona)
          biz.add_organization(org)
          business_orgs << org
          org_repos << org_repo
        end
        puts "Created business organizations"
        biz_org_1 = business_orgs.first
        biz_org_1_repo = org_repos.first
        BusinessTeamOrgAssignment.find_or_create_by!(business_team: bt_select, organization: biz_org_1)

        biz_user_ids = []
        biz_users = []
        MEMBER_USERS.times do |user_num|
          biz_user = Seeds::Objects::User.create(login: "biz-user-#{user_num}")
          biz_user_ids << biz_user.id
          biz_users << biz_user
        end
        biz.add_user_accounts(biz_user_ids)
        puts "Added users to business"

        biz_teams.each do |team|
          biz_users.each do |user|
            team.add_member(user)
          end
          puts "Added users to #{team.name}"
        end

        bt_all_orgs.add_repository biz_org_1_repo, :pull
        puts "Added pull for #{bt_all_orgs.name} to #{biz_org_1_repo.name}"

        CUSTOM_ORG_ROLES.times do |org_role_num|
          custom_org_role = Seeds::Objects::Role::create(owner: biz_org_1, name: "custom-org-role-#{org_role_num}", target_type: "Organization", permissions: %w[read_audit_logs manage_organization_webhooks])
          unless bt_all_orgs.nil? || custom_org_role.nil?
            biz_org_1.grant_org_role(assignee: bt_all_orgs, role: custom_org_role)
            puts "Granted custom org role #{custom_org_role.name} to #{bt_all_orgs.name} for #{biz_org_1.name}."
          end
        end
      end
    end
  end
end
