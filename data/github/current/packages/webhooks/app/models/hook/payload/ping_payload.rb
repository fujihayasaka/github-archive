# typed: true
# frozen_string_literal: true

class Hook::Payload::PingPayload < Hook::Payload

  def to_payload_hash
    {
      zen: GitHub.random_zen,
      hook_id: hook_event.hook_id,
      hook: hook_hash,
    }
  end

  private

  def hook_hash
    case hook_event.hook.installation_target
    when Repository
      api_serialize(:repo_hook_hash, hook_event.hook)
    when Organization
      api_serialize(:org_hook_hash, hook_event.hook)
    when Business
      api_serialize(:business_hook_hash, hook_event.hook)
    when Integration
      api_serialize(:integration_hook_hash, hook_event.hook)
    when Marketplace::Listing
      api_serialize(:marketplace_listing_hook_hash, hook_event.hook)
    when SponsorsListing
      api_serialize(:sponsors_listing_hook_hash, hook_event.hook)
    else
      raise ArgumentError.new("A hook must be installed on a Repository, an Organization, a Business, an Integration, Marketplace Listing, or a Sponsors Listing.")
    end
  end

end
