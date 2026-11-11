# typed: true
# frozen_string_literal: true

module Suggester
  class OrganizationSuggester
    def initialize(viewer:, cap_filter:)
      @viewer = viewer
      @cap_filter = cap_filter
    end

    def mentions
      to_hash = Suggester::UserSerializer.new(viewer: @viewer)
      users.map(&to_hash)
    end

    private

    def users
      list = []
      list.concat(@viewer.organizations)
      list.concat(@viewer.billing_manager_organizations)
      list = @cap_filter.authorized_resources(list)

      filter = Suggester::BlockedUserFilter.new(viewer: @viewer)
      list = list.reject(&filter)

      GitHub::PrefillAssociations.prefill_associations(list, [:profile, { user_status: :organization }])
      list
    end
  end
end
