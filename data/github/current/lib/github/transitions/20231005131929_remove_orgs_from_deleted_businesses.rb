# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class RemoveOrgsFromDeletedBusinesses < Base
      include ActionView::Helpers::TextHelper

      class DeletedBusiness < ::Business
        # Override default scope (where(deleted_at: nil)) that otherwise ignores deleted businesses
        default_scope -> { including_deleted }
      end

      attr_reader :total_updated, :actor

      iterate_over :database_table, params: {
        model_class: DeletedBusiness,
        conditions: "deleted_at IS NOT NULL",
        columns: %i(id),
      }

      def after_initialize
        @total_updated = 0
        @actor = User.find_by(login: :hubot)
      end

      def perform
        super

        if dry_run?
          log "Would have removed organizations from #{pluralize(total_updated, "deleted Business")}."
        else
          log "Removed organizations from #{pluralize(total_updated, "deleted Business")}."
        end
      end

      def process_batch(items)
        items.each do |id, _|
          business = Business.including_deleted.find_by(id: id)
          next unless business&.deleted?
          next unless business.organizations_blocking_deletion?

          orgs = business.organizations
          if verbose?
            if dry_run?
              log "Would be removing #{pluralize(orgs.count, "organization")} from Business with ID #{business.id}"
            else
              log "Removing #{pluralize(orgs.count, "organization")} from Business with ID #{business.id}"
            end
          end

          unless dry_run?
            orgs.each do |org|
              write_to(model_class: Business) do
                write_to(model_class: Configuration::Entry) do
                  begin
                    business.remove_organization(org, actor: actor)
                  rescue Business::CannotRemoveOrganizationError => error
                    log "Skipping removal of #{org.login} from Business with ID #{business.id}. #{error.inspect}"
                  end
                end
              end
            end
          end
          @total_updated += 1
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

  GitHub::Transitions::RemoveOrgsFromDeletedBusinesses.new(args).run
end
