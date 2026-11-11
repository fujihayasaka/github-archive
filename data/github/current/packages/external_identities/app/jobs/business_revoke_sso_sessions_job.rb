# typed: true
# frozen_string_literal: true

class BusinessRevokeSsoSessionsJob < ApplicationJob
  queue_as :sso_session_revoke
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(business_id)
    business = Business.find_by(id: business_id)
    return unless business

    if business.external_provider_enabled?
      # Determine if SSO is enabled at the business level, get the ExternalProvider for the business
      # and destroy all of the external_identity_sessions for that ExternalProvider.
      provider = business.external_provider
      if provider
        ActiveRecord::Base.connected_to(role: :writing) do
          ExternalIdentitySession::SsoProviderLookup.new(provider).destroy_all_in_batches
        end
      end
    else
      # If SSO is not enabled at the business level, but is enabled on at least one organization owned by the business,
      # get a list of the organizations belonging to the business that have SSO enabled.
      # Iterate through that list of organizations and get the saml provider for that org,
      # and destroy all external_identity_sessions belonging to that saml provider.

      # We iterate effectively over all organizations to find those with SSO enabled.
      business.organizations.find_each do |org|
        if org.saml_sso_enabled?
          org_provider = org.saml_provider
          if org_provider
            ActiveRecord::Base.connected_to(role: :writing) do
              ExternalIdentitySession::SsoProviderLookup.new(org_provider).destroy_all_in_batches
            end
          end
        end
      end
    end
  end
end
