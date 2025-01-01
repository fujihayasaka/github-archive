# typed: true
# frozen_string_literal: true

module UserLists
  class CreateDialogTemplateComponent < ApplicationComponent
    private

    def render?
      logged_in?
    end
  end
end
