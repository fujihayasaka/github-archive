# typed: true
# frozen_string_literal: true

module UserLists
  class UnstarDialogTemplateComponent < ApplicationComponent
    private

    def render?
      logged_in?
    end
  end
end
