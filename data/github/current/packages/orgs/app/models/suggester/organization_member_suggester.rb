# typed: true
# frozen_string_literal: true

module Suggester
  class OrganizationMemberSuggester
    def initialize(viewer:, org:, cap_filter: nil)
      @viewer = viewer
      @org = org
      @cap_filter = cap_filter
    end

    def mentions
      format = Suggester::MentionSerializer.new(viewer: @viewer)
      format.dump(users, teams)
    end

    private

    def suggested_users
      list = []

      list.concat(@org.visible_users_for(@viewer))
      list.concat(@viewer.following_for_viewer(@viewer))
      list.concat(@viewer.organizations)
      list.concat(@viewer.billing_manager_organizations)

      filter = BlockedUserFilter.new(viewer: @viewer)

      list.reject(&filter)
    end

    def suggested_teams
      @org.visible_teams_for(@viewer)
    end

    def users
      list = @cap_filter.authorized_resources(suggested_users)

      GitHub::PrefillAssociations.prefill_associations(list, :profile)
      list
    end

    def teams
      @cap_filter.authorized_resources(suggested_teams)
    end
  end
end
