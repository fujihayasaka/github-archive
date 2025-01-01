# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CleanupDeletedUsersBundledLicenseAssignments < Base
      class BundledLicenseAssignment < ApplicationRecord::Domain::Billing
        self.table_name = :bundled_license_assignments
      end

      iterate_over :database_table, params: {
        model_class: BundledLicenseAssignment,
        columns: %i[user_id],
        conditions: "user_id IS NOT NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        batch_user_ids = items.values.flat_map(&:values).uniq
        user_ids = User.where(id: batch_user_ids).pluck(:id)
        missing_user_ids = batch_user_ids - user_ids

        log "Missing user ids: #{missing_user_ids.join(', ')}"

        update_blas = ::Licensing::BundledLicenseAssignment.where(user_id: missing_user_ids)

        update_blas.each do |bla|
          log "#{dry_run? ? "Would be setting" : "Setting"} `user_id: nil` on bundled license assignment #{bla.id}"

          unless dry_run?
            write_to(model_class: BundledLicenseAssignment) do
              bla.update!(user_id: nil)
            end
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

  GitHub::Transitions::CleanupDeletedUsersBundledLicenseAssignments.new(args).run
end
