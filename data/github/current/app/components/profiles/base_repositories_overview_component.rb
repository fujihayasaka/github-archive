# typed: true
# frozen_string_literal: true

module Profiles
  class BaseRepositoriesOverviewComponent < ApplicationComponent

    VIEW_AS_OPTIONS = [nil, "public", "member"].freeze

    # Public: Initialize a BaseRepositoriesOverviewComponent
    #
    # viewing_as_member         - Optional. Boolean to determine if the component
    #                             should show the members-only view. Will be true if
    #                             the current user is a member of the organization,
    #                             and if params[:view_as] is set to "member".
    #                             Defaults to false.
    # view_as                   - Optional. A query param, can be "member",
    #                             "public", or nil based on current viewing option.
    def initialize(
      any_pinnable_items:,
      has_pinned_items:,
      items:,
      profile_user:,
      viewer_can_change_pinned_items:,
      viewing_as_member: false,
      view_as: nil
    )
      @any_pinnable_items = any_pinnable_items
      @has_pinned_items = has_pinned_items
      @items = items
      @profile_user = profile_user
      @viewer_can_change_pinned_items = viewer_can_change_pinned_items
      @viewing_as_member = fetch_or_fallback([true, false], viewing_as_member, false)
      @view_as = fetch_or_fallback(VIEW_AS_OPTIONS, view_as, nil)
    end

    private

    attr_reader :items, :profile_user, :view_as

    delegate :profile_click_tracking_attrs, to: :helpers

    def any_pinnable_items?
      @any_pinnable_items
    end

    def has_pinned_items?
      @has_pinned_items
    end

    def viewing_as_member?
      @viewing_as_member
    end

    def user_is_viewer?
      profile_user == current_user
    end

    def viewer_can_change_pinned_items?
      @viewer_can_change_pinned_items
    end

    def enterprise_managed_user_enabled?
      (profile_user.user? && profile_user.is_enterprise_managed?) || (profile_user.organization? && profile_user.enterprise_managed_user_enabled?)
    end

  end
end
