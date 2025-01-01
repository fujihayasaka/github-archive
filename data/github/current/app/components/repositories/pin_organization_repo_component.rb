# typed: true
# frozen_string_literal: true

module Repositories
  class PinOrganizationRepoComponent < ApplicationComponent

    include FeatureFlagHelper

    attr_reader :repository, :owner, :can_pin_profile_items

    def initialize(repository:)
      @repository = repository
      @owner = repository.owner
    end

    def before_render
      @can_pin_profile_items = @owner.can_pin_profile_items?(current_user)
    end

    def render?
      return false unless logged_in?
      return false unless can_pin_profile_items || repository_is_pinnable_for_current_user?

      repository_is_pinnable?
    end

    private

    def public_checkbox_disabled?
      !repository_is_pinned_publicly? && !pinned_items_remaining_publicly?
    end

    def internal_checkbox_disabled?
      !repository_is_pinned_internally? && !pinned_items_remaining_internally?
    end

    def user_checkbox_disabled?
      !repository_is_pinned_for_current_user? && !pinned_items_remaining_for_current_user?
    end

    memoize def repository_is_pinned_publicly?
      owner.pinned_repository?(repository)
    end

    memoize def repository_is_pinned_internally?
      owner.pinned_repository?(repository, internal_view: true)
    end

    memoize def repository_is_pinned_for_current_user?
      current_user.pinned_repository?(repository)
    end

    def repository_is_pinnable?
      repository_is_pinnable_publicly? || repository_is_pinnable_internally? || repository_is_pinnable_for_current_user?
    end

    memoize def repository_is_pinnable_publicly?
      can_pin_profile_items && repository.public?
    end

    memoize def repository_is_pinnable_internally?
      can_pin_profile_items
    end

    memoize def repository_is_pinnable_for_current_user?
      repository.public? && repository.contributor_of_any_kind?(current_user)
    end

    memoize def pinned_items_remaining_publicly?
      owner.pinned_items_remaining > 0
    end

    memoize def pinned_items_remaining_internally?
      owner.pinned_items_remaining(internal_view: true) > 0
    end

    memoize def pinned_items_remaining_for_current_user?
      current_user.pinned_items_remaining > 0
    end
  end
end
