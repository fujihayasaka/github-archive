# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner

    class CopilotBusinessSeat < Seeds::Runner

      sig { returns(String) }
      def self.help
        <<~HELP
        Creates a Copilot business seat for a business and assigns it to a user.
        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        business = options[:business_slug] ? ::Business.find_by!(slug: options[:business_slug]) : Seeds::Objects::Business.github
        user = options[:login] ? ::User.find_by!(login: options[:login]) : Seeds::Objects::User.monalisa

        if business
          copilot_business = Copilot::Business.new(business)

          # The second argument of assign is the inviting user of the Copilot seat and this user
          # must be an owner of the business.
          copilot_business.assign([user], business.owners.first)
        end
      end
    end
  end
end
