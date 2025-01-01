# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class AddAzureBillingTargetToCopilotStandaloneAccounts < Base
      iterate_over :csv, params: {
        csv_file: "lib/github/transitions/20250415142628_add_azure_billing_target_to_copilot_standalone_accounts.csv",
        csv_read_opts: { headers: true },
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log("Processing batch of #{items.size} items starting with row #{items.keys.first}")

        items.each do |(_, row)|
          business_slug = row[:business_slug]
          business_id = row[:business_id]

          business = Business.find_by(id: business_id)
          next log("Skipping business #{business_id} because Business record does not exist") if business.nil?
          next log("Skipping business #{business.id} because slug #{business.slug} it's not matching slug #{business_slug} from CSV") if business.slug != business_slug
          next log("Skipping business #{business.id} (#{business.slug}) because it's not on Basic plan (Copilot Standalone)") unless business.seats_plan_basic?
          next log("Skipping business #{business.id} (#{business.slug}) because it already has an active enterprise agreement") if business.enterprise_agreements.active.any?

          business_copilot_standalone_seats = ::Copilot::Seat.joins(:seat_assignment).where(copilot_seat_assignments: { owner_id: business.id }).count
          next log("Skipping business #{business.id} (#{business.slug}) because it has #{business_copilot_standalone_seats} Copilot seats") unless business_copilot_standalone_seats.zero?

          if dry_run?
            log("Would have created enterprise agreement for business #{business.id} (#{business.slug})")
          else
            write_to(model_class: ::Licensing::EnterpriseAgreement) do
              license = ::Licensing::EnterpriseAgreement.create(
                business: business,
                agreement_id: SecureRandom.uuid,
                category: :metered,
                status: :active,
                seats: 0,
                ends_at: GitHub::Validations::DatetimeInSupportedRangeValidator::TIME_MAX
              )
              if license.persisted?
                log("Created enterprise agreement for business #{business.id} (#{business.slug})")
              else
                log("Failed to create enterprise agreement for business #{business.id} (#{business.slug}). Errors: #{license.errors&.full_messages&.join(", ")}.")
              end
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

  GitHub::Transitions::AddAzureBillingTargetToCopilotStandaloneAccounts.new(args).run
end
