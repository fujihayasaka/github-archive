# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::ListComponent < ApplicationComponent
  # orgs - a WillPaginate::Collection of Organization records to show
  # active_only - Boolean indicating whether the "active sponsors only" filter has been applied when loading orgs
  def initialize(orgs:, active_only:)
    @orgs = orgs
    @active_only = active_only
  end

  private

  def render?
    GitHub.sponsors_enabled? && logged_in?
  end

  def active_sponsors_only?
    @active_only
  end

  memoize def orgs
    GitHub::PrefillAssociations.prefill_associations(@orgs, :profile)
    GitHub::PrefillAssociations.prefill_associations(@orgs, :sponsors_customer)
    GitHub::PrefillAssociations.prefill_associations(@orgs, :organization_profile)
    @orgs
  end

  memoize def org_ids
    orgs.map(&:id)
  end

  memoize def sponsorship_counts_by_org_id
    Sponsorship.active.from_sponsor(org_ids).group(:sponsor_id).count
  end

  memoize def org_ids_with_invoiced_sponsorship_transfers
    InvoicedSponsorshipTransfer.for_sponsor(org_ids).distinct.pluck(:sponsor_id).to_set
  end
end
