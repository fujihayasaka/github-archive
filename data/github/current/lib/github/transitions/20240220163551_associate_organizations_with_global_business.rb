# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# GHES-only transition to associate any unassociated Organizations with the
# global Business.
module GitHub
  module Transitions
    class AssociateOrganizationsWithGlobalBusiness < Base
      iterate_over :database_table, params: {
        model_class: Organization,
        conditions: "type = 'Organization' AND login != '#{Business::EXCLUDE_FROM_SINGLE_BUSINESS_ORGS.first}'",
        columns: %i[login],
      }

      sig { void }
      def run
        unless GitHub.enterprise?
          raise RuntimeError, "This transition cannot be run outside of the enterprise runtime environment."
        end

        super
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.each do |id, _|
          org = Organization.find_by id: id
          next unless org
          next if org.business.present?

          if dry_run?
            log "Would be adding Organization with ID #{org.id} to global Business."
          else
            log "Adding Organization with ID #{org.id} to global Business."
            write_to(model_class: Business) do
              GitHub.global_business.add_organization(org)
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

  GitHub::Transitions::AssociateOrganizationsWithGlobalBusiness.new(args).run
end
