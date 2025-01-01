# typed: true
# frozen_string_literal: true

module UserLists
  class MenuComponent < ApplicationComponent
    # repository - The Repository to add/remove from the current user's lists; required if `repo_owner_login`
    #              and `repo_name` are not provided.
    # repo_owner_login - The owner of the repository to add/remove from the current user's lists; required if
    #                    `repository` is not provided.
    # repo_name - The name of the repository to add/remove from the current user's lists; required if `repository`
    #             is not provided.
    # repo_id - The id of the repository to add/remove from the current user's lists; required if `repository`
    #             is not provided.
    # id_suffix - A suffix to append to the component's id to ensure that it's unique within the rendered page. The
    #             ID contains the repository ID, but if this component is rendered more than once on the same page
    #             with the same repository, a different suffix must be provided each time to avoid harming
    #             accessibility.
    def initialize(repository: nil, repo_owner_login: nil, repo_name: nil, repo_id: nil, id_suffix: "", data: {})
      @data = data
      @id_suffix = id_suffix
      if repository
        @repo_owner_login = repository.owner_display_login
        @repo_name = repository.name
        @repo_id = repository.id
      else
        @repo_owner_login = repo_owner_login
        @repo_name = repo_name
        @repo_id = repo_id
      end
    end

    private

    def render?
      repo_owner_login.present? && repo_name.present? && logged_in?
    end

    attr_reader :repo_owner_login, :repo_name, :repo_id, :id_suffix, :data

    def menu_id
      ["details-user-list", repo_id, id_suffix].select(&:present?).join("-")
    end

    def user_list_menu_src
      repo_user_lists_path(repo_owner_login, repo_name)
    end
  end
end
