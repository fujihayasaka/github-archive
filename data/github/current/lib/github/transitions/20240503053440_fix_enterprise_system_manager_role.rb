# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class FixEnterpriseSystemManagerRole < Base
      sig do
        override.void
      end
      def perform
        create_roles
      end

      private

      sig { void }
      def create_roles
        affected_rows = 0
        if dry_run?
          log("[dry_run] would update role enterprise_security_manager_role target_type Business")
        else
          write_to(model_class: Role) do
            r = Role.enterprise_security_manager_role
            if r.nil?
              log("enterprise_security_manager_role not found, skipping")
              return
            end
            r.target_type = "Business"
            unless r.valid?
              log("enterprise_security_manager_role is invalid, skipping")
              return
            end
            r.save!

            unless r.class.to_s == "EnterpriseRole"
              log("enterprise_security_manager_role is not an EnterpriseRole")
            end
          end
        end

        log("updated enterprise_security_manager") if verbose?
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::FixEnterpriseSystemManagerRole.new(args).run
end
