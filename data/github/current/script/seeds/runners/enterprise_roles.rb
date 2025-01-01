# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class EnterpriseRoles < Seeds::Runner
      FEATURE_FLAGS = %w(
        custom_enterprise_role_feature
        fix_enterprise_role_plan_validation
        use_biz_audit_log_fgp_api
        use_biz_audit_log_fgp_ui
      )

      def self.help
        <<~HELP
        Enable the enterprise custom role feature on the default GitHub, Inc enterprise. Create a custom role with all current enterprise FGPs and assign it to an 'enterprise_member' user.

        To run the seed script:
          1. script/server
          2. bin/seed enterprise_roles
        HELP
      end

      def self.run(options = {})
        FEATURE_FLAGS.each do |flag|
          Seeds::Objects::FeatureFlag.enable(feature_flag: flag)
        end

        biz = Seeds::Objects::Business.github
        org = Seeds::Objects::Organization.github

        fgp_user = Seeds::Objects::User.create(login: "enterprise-all-permissions-member")
        org.add_member fgp_user
        puts "Created '#{fgp_user.name}' user who has all enterprise FGPs assigned."

        no_fgp_user = Seeds::Objects::User.create(login: "enterprise-no-permissions-member")
        org.add_member no_fgp_user
        puts "Created '#{no_fgp_user.name}' user who has no enterprise FGPs assigned."

        fgps = Permissions::FineGrainedPermissionIm.where(target_type: "Business").map(&:action)
        custom_role = Seeds::Objects::Role::create(
          owner: biz,
          name: "all_fgps_enterprise_role",
          target_type: "Business",
          permissions: fgps)
        puts "Created the '#{custom_role.name}' role with the following permissions: #{fgps}"

        existing_assignment = UserRole.find_by(actor: fgp_user, target: biz, role_id: custom_role.id)
        if existing_assignment
          puts "'#{custom_role.name}' role already assigned to '#{fgp_user.name}' user"
        else
          Permissions::Granters::RoleGranter.new(actor: fgp_user, target: biz, role: custom_role).grant!
          puts "Assigned '#{custom_role.name}' role to '#{fgp_user.name}' user"
        end

      end
    end
  end
end
