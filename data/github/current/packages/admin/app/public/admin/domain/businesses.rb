# typed: strict
# frozen_string_literal: true

module Admin
  class Domain
    class Businesses < GH::Domain::Base
      # Finds a Business by its ID.
      #
      # @param id [Integer] The Business ID.
      # @return [Admin::IBusiness, nil] The business if found, otherwise nil.
      sig { params(id: Integer).returns(T.nilable(Admin::IBusiness)) }
      def by_id(id)
        return nil if id <= 0

        Business.find_by(id: id)
      end

      # Finds a Business by its slug.
      #
      # @param slug [String] The Business slug.
      # @return [Admin::IBusiness, nil] The business if found, otherwise nil.
      sig { params(slug: String).returns(T.nilable(Admin::IBusiness)) }
      def by_slug(slug)
        return nil if slug.blank?

        Business.find_by(slug: slug)
      end

      # Finds the Business that owns a given organization.
      #
      # @param org_id [Integer] The Organization ID.
      # @return [Admin::IBusiness, nil] The owning business, otherwise nil.
      sig { params(org_id: Integer).returns(T.nilable(Admin::IBusiness)) }
      def from_org_id(org_id)
        return nil if org_id <= 0

        Business.from_org_id(org_id)
      end

      # Finds a Business by ID, including soft-deleted records.
      #
      # @param id [Integer] The Business ID.
      # @return [Admin::IBusiness, nil] The business if found (including deleted), otherwise nil.
      sig { params(id: Integer).returns(T.nilable(Admin::IBusiness)) }
      def including_deleted_by_id(id)
        return nil if id <= 0

        Business.including_deleted.find_by(id: id)
      end

      # Returns the organization IDs belonging to a given business.
      #
      # @param business_id [Integer] The Business ID.
      # @return [Array<Integer>] The organization IDs.
      sig { params(business_id: Integer).returns(T::Array[Integer]) }
      def organization_ids(business_id)
        return [] if business_id <= 0

        Business::OrganizationMembership.where(business_id: business_id).pluck(:organization_id)
      end
    end
  end
end
