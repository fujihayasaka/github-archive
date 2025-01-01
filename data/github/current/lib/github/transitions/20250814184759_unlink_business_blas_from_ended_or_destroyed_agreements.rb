# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UnlinkBusinessBlasFromEndedOrDestroyedAgreements < Base
      class BundledLicenseAssignment < ApplicationRecord::Domain::Billing
        self.table_name = :bundled_license_assignments
      end

      iterate_over :database_table, params: {
        model_class: BundledLicenseAssignment,
        columns: %i[business_id enterprise_agreement_number],
        conditions: "business_id IS NOT NULL"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "#{dry_run? ? "Would be evaluating clean up" : "Evaluating clean up"} for bundled license assignment IDs: #{items.keys.join(', ')}"

        bla_agreement_ids = items.values.map { |bla| bla[:enterprise_agreement_number] }.uniq

        log "#{dry_run? ? "Would be evaluating clean up" : "Evaluating clean up"} for enterprise agreement IDs: #{bla_agreement_ids.join(', ')}"

        # Find all enterprise agreements for the given IDs
        all_agreements = ::Licensing::EnterpriseAgreement.where(agreement_id: bla_agreement_ids)

        # Find ended agreements
        ended_agreements = all_agreements.select { |agreement| agreement.ended? }
        ended_agreement_ids = ended_agreements.map(&:agreement_id)

        # Find destroyed agreements (those that don't exist in the database)
        existing_agreement_ids = all_agreements.pluck(:agreement_id)
        destroyed_agreement_ids = bla_agreement_ids - existing_agreement_ids

        # Group items by agreement status
        bla_ids_from_ended_agreements = []
        bla_ids_from_destroyed_agreements = []
        items.each do |bla_id, bla|
          agreement_number = bla[:enterprise_agreement_number]
          if ended_agreement_ids.include?(agreement_number)
            log "#{dry_run? ? "Would unlink" : "Unlink"} bundled license assignment ID #{bla_id} from business ID #{bla[:business_id]} due to ended enterprise agreement #{bla[:enterprise_agreement_number]}"
            bla_ids_from_ended_agreements << bla_id
          elsif destroyed_agreement_ids.include?(agreement_number)
            log "#{dry_run? ? "Would unlink" : "Unlink"} bundled license assignment ID #{bla_id} from business ID #{bla[:business_id]} due to destroyed enterprise agreement #{bla[:enterprise_agreement_number]}"
            bla_ids_from_destroyed_agreements << bla_id
          end
        end

        return if dry_run?

        # See `packages/licensing/app/models/licensing/enterprise_agreement.rb` for more details on when we do/don't revoke on assignment unlink
        write_to(model_class: BundledLicenseAssignment) do
          ::Licensing::BundledLicenseAssignment.where(id: bla_ids_from_ended_agreements).update_all(business_id: nil, revoked: true)
          ::Licensing::BundledLicenseAssignment.where(id: bla_ids_from_destroyed_agreements).update_all(business_id: nil)
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

  GitHub::Transitions::UnlinkBusinessBlasFromEndedOrDestroyedAgreements.new(args).run
end
