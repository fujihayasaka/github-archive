# typed: true
# frozen_string_literal: true

module UserLists
  class EditDialogComponent < ApplicationComponent
    # user_list - A UserList model used to render the initial state of each dialog input field and to detect validation
    #   errors to display.
    def initialize(user_list:)
      @user_list = user_list
    end

    private

    attr_reader :user_list

    def render?
      logged_in? && user_list.present?
    end
  end
end
