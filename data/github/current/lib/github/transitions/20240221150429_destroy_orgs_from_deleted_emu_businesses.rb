# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DestroyOrgsFromDeletedEmuBusinesses < Base
      include ActionView::Helpers::TextHelper

      class DeletedBusiness < ::Business
        # The default_scope is used to filter out deleted businesses by default in ::Business.
        # Since this transition is about destroying organizations from deleted EMU businesses, the
        # default_scope needs to be overridden here to have deleted businesses included.
        default_scope -> { including_deleted }
      end

      sig { returns(T.nilable(User)) }
      attr_reader :actor

      # Iterate over EMU businesses that have been deleted.
      iterate_over :database_table, params: {
        model_class: DeletedBusiness,
        conditions: "business_type = 1 AND deleted_at IS NOT NULL"
      }

      sig { override.void }
      def after_initialize
        @actor = T.let(User.ghost, T.nilable(User))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.each do |id, _|
          business = DeletedBusiness.find_by(id: id)
          return unless business.present?
          return unless T.must(business.deleted_at) < Business::RESTORABLE_PERIOD.ago
          return unless business.organizations.any?

          orgs = business.organizations

          if dry_run?
            log "Would have destroyed #{pluralize(orgs.count, "organization")} from Business with ID #{business.id}"
          else
            log "Destroying #{pluralize(orgs.count, "organization")} from Business with ID #{business.id}"

            orgs.each do |org|
              write_to(model_class: Organization) do
                org.async_destroy(actor)
                log "Destroying Organization with login #{org.login} from Business with ID #{business.id}."
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

  GitHub::Transitions::DestroyOrgsFromDeletedEmuBusinesses.new(args).run
end
