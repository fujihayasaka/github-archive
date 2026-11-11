# typed: true
# frozen_string_literal: true

module Releases
  class DeleteReleaseConfirmationComponent < ApplicationComponent
    def initialize(dialog_id:, release:)
      @dialog_id = dialog_id
      @release = release
    end

    private

    attr_reader :dialog_id, :release

    memoize def has_discussion?
      release.discussion
    end
  end
end
