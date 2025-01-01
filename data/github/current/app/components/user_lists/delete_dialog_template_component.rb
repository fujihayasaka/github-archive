# typed: true
# frozen_string_literal: true

module UserLists
  class DeleteDialogTemplateComponent < ApplicationComponent
    # user_list - the UserList to show a form for deleting
    def initialize(user_list:)
      @user_list = user_list
    end

    memoize def template_dom_id
      "user-list-#{user_list.slug}-delete-dialog-template"
    end

    private

    attr_reader :user_list

    def render?
      logged_in? && user_list&.persisted?
    end

    memoize def box_title_dom_id
      "user-list-#{user_list.slug}-delete-box-title"
    end
  end
end
