# typed: true
# frozen_string_literal: true

module Releases
  class DeleteConfirmationComponent < ApplicationComponent
    def initialize(dialog_id:, release:)
      @dialog_id = dialog_id
      @release = release
    end

    def call
      if is_release?
        render(Releases::DeleteReleaseConfirmationComponent.new(dialog_id: dialog_id, release: release))
      elsif is_protected_tag?
        render(Releases::DeleteProtectedTagConfirmationComponent.new(dialog_id: dialog_id, release: release,
          ruleset_protected: is_ruleset_protected?))
      else
        render(Releases::DeleteTagConfirmationComponent.new(dialog_id: dialog_id, release: release))
      end
    end

    private

    attr_reader :dialog_id, :release

    def is_release?
      !release.new_record?
    end

    def is_protected_tag?
      !is_release? && (release.tag_protected? || release.tag_protected_by_ruleset?)
    end

    memoize def is_ruleset_protected?
      release.tag_protected_by_ruleset?
    end
  end
end
