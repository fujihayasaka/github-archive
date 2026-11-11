# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class Dependabot < Seeds::Runner
      def self.help
        <<~HELP
        Enable Dependabot on an account
        HELP
      end

      def self.run(options = {})
        owner_name = options[:owner]
        runner = new(owner_name:)

        puts "Starting..."
        puts

        runner.ensure_dependabot
        puts "✅ Dependabot: #{runner.dependabot_app.bot.display_login}"

        runner.ensure_owner
        puts "✅ Owner: #{runner.owner.display_login}"

        runner.install_dependabot_on_owner
        puts "✅ Dependabot Installed on Owner"

      end

      attr_reader :owner_name, :owner, :dependabot_app

      def initialize(owner_name: nil)
        @owner_name = owner_name
      end

      def ensure_dependabot
        @dependabot_app = Seeds::Objects::Integration.create_dependabot_integration
      end

      def ensure_owner
        # Ensure monalisa is created before looking up the owner
        _ = Seeds::Objects::User.monalisa

        @owner = if owner_name
          ::User.find_by(login: owner_name) || Seeds::Objects::Organization.create(login: owner_name, admin: Seeds::Objects::User.monalisa)
        else
          Seeds::Objects::Organization.github
        end

        if owner.organization?
          if owner.business.present?
            owner.business.mark_advanced_security_as_purchased_for_entity(actor: owner.admins.first)
          else
            owner.mark_advanced_security_as_purchased_for_entity(actor: owner.admins.first)
          end
        end
      end

      def install_dependabot_on_owner
        Seeds::Objects::Integration.install(
          integration: @dependabot_app,
          target: @owner,
          repo: [],
          installer: @owner.admins.first
        )
      end
    end
  end
end
