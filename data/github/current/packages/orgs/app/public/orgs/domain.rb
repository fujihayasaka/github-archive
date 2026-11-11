# typed: strict
# frozen_string_literal: true

module Orgs
  class Domain < GH::Domain::Base
    accessor Orgs::Domain::Teams
    accessor Orgs::Domain::CustomProperties

    BATCH_SIZE = 1000

    # Finds an active organization by its ID.
    #
    # @param id [Integer] The organization ID.
    # @return [IOrganization, nil] The organization if found, otherwise nil.
    sig { params(id: Integer).returns(T.nilable(IOrganization)) }
    def by_id(id)
      return nil if id <= 0

      Organization.active.find_by(id: id.to_i)
    end

    # Finds an active organization by its login name.
    #
    # @param name [String] The organization login name.
    # @return [IOrganization, nil] The organization if found, otherwise nil.
    sig { params(name: String).returns(T.nilable(IOrganization)) }
    def by_name(name)
      return nil if name.blank?

      Organization.active.find_by(login: name)
    end

    # Returns a hash mapping organization IDs by their associated business IDs.
    #
    # @param organization_ids [Array<Integer>] The list of organization IDs to group.
    # @return [Hash<Integer, Array<Integer>>] A hash where keys are business IDs and values are arrays of organization IDs.
    sig { params(organization_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
    def group_organization_ids_by_business(organization_ids)
      organization_ids.each_slice(BATCH_SIZE).each_with_object({}) do |ids_batch, hash|
        Business::OrganizationMembership
          .where(organization_id: ids_batch)
          .pluck(:business_id, :organization_id)
          .each { |business_id, org_id| (hash[business_id] ||= []) << org_id }
      end
    end
  end
end
