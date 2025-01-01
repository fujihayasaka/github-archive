# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BusinessOrganizations < Platform::Loader
      def self.load(business, org_ids)
        organizations = self.for(business).fetch(org_ids)
        Promise.resolve(organizations)
      end

      def initialize(business)
        @business = business
      end

      def fetch(org_ids)
        ::Organization.joins(:business_membership).
          where(business_organization_memberships: { business_id: @business.id, organization_id: org_ids })
      end
    end
  end
end
