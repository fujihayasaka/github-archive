# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ResendLostContactSalesLeads < Base
      iterate_over :database_table, params: {
        model_class: Site::EnterpriseContactRequest,
        conditions: "status != 1 AND created_at > '2025-03-27'",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if dry_run?
          log "Would have resent #{items.size} contact sales leads"
          return
        end

        items.keys.each do |id|
          EnterpriseContactRequestSubmissionJob.perform_later(id)
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

  GitHub::Transitions::ResendLostContactSalesLeads.new(args).run
end
