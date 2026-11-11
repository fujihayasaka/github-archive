# typed: true
# frozen_string_literal: true

module Releases
  class PublishConfirmationDialogComponent < ApplicationComponent
    def initialize(dialog_id:)
      @dialog_id = dialog_id
    end

    private

    attr_reader :dialog_id
  end
end
