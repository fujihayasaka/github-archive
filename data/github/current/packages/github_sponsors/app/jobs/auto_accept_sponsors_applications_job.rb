# typed: true
# frozen_string_literal: true

require "github/sql/readonly"

class AutoAcceptSponsorsApplicationsJob < ApplicationJob
  queue_as :sponsors_application_processing

  retry_on_dirty_exit

  def perform
    Failbot.push(app: "github-sponsors")

    GitHub::SQL::Readonly.new(listing_id_iterator.batches).each do |rows|
      listings = SponsorsListing.where(id: rows.ids)

      listings.each do |listing|
        next unless listing.auto_acceptable?

        result = SponsorsListing.throttle_writes_with_retry(max_retry_count: 8) do
          Sponsors::AcceptSponsorsMembership.call(
            sponsorable: listing.sponsorable,
            actor: nil,
            automated: true,
          )
        end

        unless result.success?
          Failbot.report(
            AutoAcceptError.new("Failed to auto accept listing (#{listing.id})"),
            sponsors_listing_id: listing.id,
            errors: result.errors,
          )
        end
      end
    end
  end

  class AutoAcceptError < StandardError; end

  private

  def listing_id_iterator
    scope = SponsorsListing
      .with_waitlisted_state
      .with_auto_acceptable_billing_country
      .not_ignored
      .select(:id)
      .distinct

    GitHub::QueryBatching::ScopeIterator.new(scope, batch_size: 100)
  end
end
