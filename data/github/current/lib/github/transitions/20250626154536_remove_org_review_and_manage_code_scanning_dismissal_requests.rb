# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class RemoveOrgReviewAndManageCodeScanningDismissalRequests < Base
      class RolePermission < ApplicationRecord::Iam
        self.table_name = :role_permissions
      end

      iterate_over :database_table, params: {
        model_class: RolePermission,
        conditions: "action = 'org_review_and_manage_code_scanning_dismissal_requests'"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        scope = RolePermission.where(id: items.keys).where(action: :org_review_and_manage_code_scanning_dismissal_requests)

        if dry_run?
          log "would remove #{scope.size} items from the role_permissions"
        else
          write_to(model_class: RolePermission) do
            scope.delete_all
          end
        end
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

  GitHub::Transitions::RemoveOrgReviewAndManageCodeScanningDismissalRequests.new(args).run
end
