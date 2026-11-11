# typed: true
# frozen_string_literal: true

module Repositories
  class PinComponent < ApplicationComponent
    attr_reader :repository, :owner

    def initialize(repository:)
      @repository = repository
      @owner = repository.owner
    end

    def render?
      return false unless owner.can_pin_profile_items?(current_user)

      repository_is_pinned? || repository_is_pinnable?
    end

    private

    def form_method
      repository_is_pinned? ? :delete : :post
    end

    def form_label
      repository_is_pinned? ? "Unpin" : "Pin"
    end

    def title
      if repository_is_pinnable? && !repository_is_pinned?
        owner_name = owner == current_user ? "your" : "#{owner.display_login}'s"

        if pinned_items_remaining?
          "Pin this repository to #{owner_name} profile"
        else
          "No pin slots remaining in #{owner_name} profile"
        end
      end
    end

    def button_disabled?
      repository_is_pinnable? && !repository_is_pinned? && !pinned_items_remaining?
    end

    memoize def repository_is_pinned?
      owner.pinned_repository?(repository)
    end

    memoize def repository_is_pinnable?
      repository.public?
    end

    memoize def pinned_items_remaining?
      owner.pinned_items_remaining > 0
    end
  end
end
