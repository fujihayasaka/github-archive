# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class RemoveCreateAndEditDiscussionActionsFromTriageRole < Base
      sig { override.void }
      def perform
        if dry_run?
          reconcile
        else
          write_to(model_class: RolePermission) do
            reconcile
          end
        end
      end

      private

      sig { void }
      def reconcile
        GitHub.system_roles.reconcile(
          purge: true,
          dry_run: dry_run?,
          verbose: verbose?,
        )
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

  GitHub::Transitions::RemoveCreateAndEditDiscussionActionsFromTriageRole.new(args).run
end
