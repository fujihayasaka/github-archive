# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class ESM < Seeds::Runner
      FEATURE_FLAGS = %w(
        enterprise_teams_crud
        custom_enterprise_role_feature
        enterprise_teams_org_roles
        enterprise_teams_esm
        enterprise_teams_org_assignment
        enterprise_teams_attributes_include_business_teams
      )

      def self.help
        <<~HELP
        Enable the Enterprise Security Manager (ESM) enterprise role on the default GitHub, Inc enterprise.
        Creates an esm enterprise team with one user and assigns the Enterprise Security Manager role to the team.

        To run the seed script:
          1. script/server
          2. bin/seed esm
        HELP
      end

      def self.run(options = {})
        FEATURE_FLAGS.each do |flag|
          Seeds::Objects::FeatureFlag.enable(feature_flag: flag)
        end

        biz = Seeds::Objects::Business.github

        esm_team = BusinessTeam.find_or_create_by!(name: "esm enterprise team", business: biz, organization_selection_type: :all)
        puts "Created esm enterprise team"

        user = Seeds::Objects::User.create(login: "esm-user")
        user2 = Seeds::Objects::User.create(login: "biz-user")
        biz.add_user_accounts([user.id, user2.id])
        puts "Created esm-user and added to the business"
        esm_team.add_member(user, { caller_type: :business_team })
        puts "Added esm-user to the esm enterprise team"

        Permissions::Granters::EnterpriseRoleGranter.grant_role(
          actor: esm_team,
          target: biz,
          role: Role.enterprise_security_manager_role
        )
        puts "Assigned Enterprise Security Manager role to the esm enterprise team"
      end
    end
  end
end
