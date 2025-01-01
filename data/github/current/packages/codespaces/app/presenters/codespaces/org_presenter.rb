# typed: strict
# frozen_string_literal: true

module Codespaces
  class OrgPresenter
    include GitHub::Memoizer

    sig { params(business: ::Business, organization: ::Organization, disable_form: T::Boolean, avatar_url: T.nilable(String)).void }
    def initialize(business:, organization:, disable_form: false, avatar_url: nil)
      @business = business
      @organization = organization
      @disable_form = disable_form
      @avatar_url = avatar_url
    end

    sig { returns(T::Boolean) }
    attr_reader :disable_form

    sig { returns(T.nilable(String)) }
    attr_reader :avatar_url

    sig { returns(T::Hash[Symbol, T.any(String, Integer)]) }
    def serialize
      {
        id: organization.id,
        displayLogin: organization.display_login,
        avatarUrl: avatar_url,
        memberCount: organization.members.size,
        enablementStatus: enablement_status.capitalize,
        path: UrlHelpers.user_path(organization),
      }
    end

    private

    sig { returns(String) }
    def enablement_status
      # If they are switching to selected organizations setting, show disabled so they can enable it
      return "disabled" unless business_delegator.codespaces_enabled_for_selected_organizations?

      business_delegator.codespaces_disabled_for_org?(organization) ? "disabled" : "enabled"
    end

    sig { returns(::Codespaces::BusinessDelegator) }
    memoize def business_delegator
      ::Codespaces::BusinessDelegator.new(@business)
    end

    sig { returns(Organization) }
    attr_reader :organization
  end
end
