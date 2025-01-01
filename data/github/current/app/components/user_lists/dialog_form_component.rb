# typed: true
# frozen_string_literal: true

module UserLists
  class DialogFormComponent < ApplicationComponent
    renders_one :prelude
    renders_one :actions_list

    # user_list - A UserList model used to populate the initial values of the form inputs and to report any validation
    # placeholder_name - An optional string to prefill the name field of the form.
    #   errors.
    def initialize(user_list:, placeholder_name: nil)
      @user_list = user_list
      @placeholder_name = placeholder_name
    end

    private

    attr_reader :user_list, :placeholder_name

    def render?
      logged_in?
    end

    def user_list_checks_src(attr:)
      params = { user: current_user, attr: attr }
      params[:list_id] = user_list.id if user_list.persisted?
      user_list_checks_path(**params)
    end

    def form_action_url
      if user_list.persisted?
        user_list_path(current_user, user_list)
      else
        user_lists_path(current_user)
      end
    end

    def form_method
      user_list.persisted? ? :put : :post
    end
  end
end
