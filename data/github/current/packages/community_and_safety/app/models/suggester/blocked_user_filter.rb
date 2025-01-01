# typed: true
# frozen_string_literal: true

module Suggester
  class BlockedUserFilter
    def initialize(viewer:)
      @viewer = viewer
      @ignored_by = viewer.ignored_by.pluck(:id).to_set
    end

    def to_proc
      proc do |user|
        user.hide_from_user?(@viewer) || user.suspended? || @ignored_by.include?(user.id)
      end
    end
  end
end
