# typed: true
# frozen_string_literal: true

module Releases
  class DeleteProtectedTagConfirmationComponent < ApplicationComponent
    def initialize(dialog_id:, release:, ruleset_protected:)
      @dialog_id = dialog_id
      @release = release
      @ruleset_protected = ruleset_protected
    end

    private

    attr_reader :dialog_id, :release, :ruleset_protected

    delegate :case_insensitive_pattern, to: :helpers
  end
end
