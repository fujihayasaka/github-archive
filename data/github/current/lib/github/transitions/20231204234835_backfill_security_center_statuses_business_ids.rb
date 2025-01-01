# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSecurityCenterStatusesBusinessIds < Base
      class MyModel < ApplicationRecord::Notify
        self.table_name = :repository_security_center_statuses
      end

      iterate_over :database_table, params: {
        model_class: MyModel,
        conditions: "business_id IS NULL",
        columns: %i[organization_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "#{dry_run? ? "Would be updating" : "Updating"} records from #{items.keys.first} to #{items.keys.last}"
        config_ids = items.keys
        organization_ids = items.values.map { |h| h[:organization_id] }.uniq.sort

        # Hash of org_id -> business_id
        org_to_biz_id = Business::OrganizationMembership
          .where("organization_id IN (?)", organization_ids)
          .pluck([:organization_id, :business_id])
          .to_h

        # We want to restructure items to be a hash of
        # organization_id -> [config_id1, config_id2]
        # This allows us to update all the config records within this batch
        org_to_config_ids = items.each_with_object({}) do |(config_id, item), result|
          (result[item[:organization_id]] ||= []) << config_id
        end

        org_to_config_ids.each do |org_id, config_ids|
          log("Updating #{config_ids} with org_id #{org_id} to be #{org_to_biz_id[org_id]}") if verbose?
          next if org_to_biz_id[org_id].nil?
          next if dry_run?

          write_to(model_class: MyModel) do
            MyModel.where(id: config_ids).update_all(business_id: org_to_biz_id[org_id])
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

  GitHub::Transitions::BackfillSecurityCenterStatusesBusinessIds.new(args).run
end
