# typed: true
# frozen_string_literal: true

module Discussions
  class SpotlightsComponent < ApplicationComponent
    extend T::Sig
    include GitHub::Memoizer

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        current_repository: T.untyped,
        spotlights: T.untyped,
        can_manage_spotlights: T.untyped,
        can_toggle_discussions_setting: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(current_repository:, spotlights:, can_manage_spotlights: false, can_toggle_discussions_setting: false, org_param: nil)
      @current_repository = current_repository
      @spotlights = spotlights
      @can_manage_spotlights = can_manage_spotlights
      @can_toggle_discussions_setting = can_toggle_discussions_setting
      @org_param = org_param
    end

    sig { returns T::Boolean }
    def is_org_level?
      org_param.present?
    end

    memoize def only_one_spotlight?
      spotlights.size == 1
    end

    private

    memoize def discussion_spotlights_full?
      DiscussionSpotlight.repository_at_limit?(current_repository)
    end
    attr_reader :current_repository, :spotlights, :can_manage_spotlights, :can_toggle_discussions_setting

    sig { returns T.nilable(String) }
    attr_reader :org_param
  end
end
