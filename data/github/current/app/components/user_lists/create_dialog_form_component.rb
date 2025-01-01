# typed: true
# frozen_string_literal: true

module UserLists
  class CreateDialogFormComponent < ApplicationComponent
    # user_list - A UserList model instance used to prepopulate form inputs and report validation errors.
    # repository_id - ID of a Repository to add to the created UserList if the form submission is successful.
    # placeholder_name - An optional string to prefill the name field of the form.
    def initialize(user_list: UserList.new, repository_id: nil, placeholder_name: nil)
      @user_list = user_list
      @repository_id = repository_id
      @placeholder_name = placeholder_name
    end

    private

    attr_reader :user_list, :repository_id, :placeholder_name

    def render?
      logged_in? && user_list.present?
    end
  end
end
