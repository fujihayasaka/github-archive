# typed: true
# frozen_string_literal: true

class Hook::Payload::MetaPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      hook_id: hook_event.hook_id,
      hook: hook_hash,
    }
  end

  def hook_hash
    hook = hook_event.hook

    options = case hook.installation_target_type
    when "Repository"
      { type: "Repository" }
    when "User"
      { type: "Organization" }
    when "Business"
      { type: "Enterprise", enterprise_id: hook.installation_target_id }
    when "Integration"
      { type: "App", app_id: hook.installation_target_id }
    when "Marketplace::Listing"
      { marketplace_listing_id: hook.installation_target_id }
    when "SponsorsListing"
      { sponsors_listing_id: hook.installation_target_id }
    else
      raise ArgumentError.new("A hook must be installed on a Repository, an Organization, a Business, an Integration, Marketplace Listing, or Sponsors Listing.")
    end

    base_hash = api_serialize(:simple_hook_hash, hook_event.hook)
    base_hash.merge(options)
  end
end
