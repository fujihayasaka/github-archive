# typed: false
# frozen_string_literal: true

module Api::RequestOwner
  # For the given API request, try to determine the organizations
  # who should be considered "owners" of this request,
  # for the purposes of attributing API consumption to orgs.
  #
  # @return [Integer, nil] Org ID or User ID, if there is one for this request
  def self.call(user:, installation:, integration:, oauth_application:)
    ActiveRecord::Base.connected_to(role: :reading) do
      # Check the installation because wherever it's installed
      # tells us who's benefitting from this API call
      if installation.present?
        installation.target
      # If this request is an OAuth app acting on a user's behalf,
      # check the owner of the OAuth app.
      elsif user.present?
        if user.using_auth_via_oauth_application?
          # There's an `.oauth_access` which is from an OAuth app
          app_owner = user.oauth_application.user
          # Only count the app owner as the request owner _if_ this user also belongs to the org.
          if user.organization_ids.include?(app_owner.id)
            app_owner
          elsif (oauth_approvals = OauthApplicationApproval.includes(:organization).where(organization_id: user.organization_ids, application_id: user.oauth_application.id)) &&
              oauth_approvals.any?
            # Among this user's orgs, choose the first one with the elevated limit
            ghec_org_approval = oauth_approvals.find { |approval| Api::RateLimitConfiguration.qualifies_for_higher_limit?(approval.organization) }
            # If no org qualifies for the higher limit, choose another one
            if ghec_org_approval
              ghec_org_approval.organization
            else
              oauth_approvals.first.organization
            end
          else
            nil
          end
        elsif user.using_auth_via_integration?
          integration.owner
        else
          # It's a user authenticating by some other means, like PAT
          nil
        end
      # If the integration is acting without a user or installation, credit the integration's owner
      elsif integration.present?
        integration.owner
      # Finally, in the rare case that an OAuth application is acting on its own,
      # without a user who has authorized it and created an oauth token, count it as the
      # OAuth app's owner's request.
      elsif oauth_application.present?
        oauth_application.user
      else
        # This situation can't be attributed to a specific owner
        nil
      end
    end
  end
end
