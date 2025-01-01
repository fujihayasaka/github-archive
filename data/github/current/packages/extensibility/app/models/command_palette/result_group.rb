# typed: true
# frozen_string_literal: true

module CommandPalette
  class ResultGroup
    attr_reader :id, :title, :global_sort, :user_sort, :repo_sort, :hint, :limits

    # limits: Hash where the key is the scope type, and value is the item limit to be shown in that scope
    #   IE: {repository: 10}
    def initialize(id:, title: "", hint: "", global_sort: 0, user_sort: 0, repo_sort: 0, limits: {})
      @id = id
      @title = title
      @hint = hint
      @global_sort = global_sort
      @user_sort = user_sort
      @repo_sort = repo_sort
      @limits = limits
    end

    def display_title
      return title if title.present?
      id.to_s.titleize
    end

    def sort_order(context = nil)
      global_sort
    end
  end
end
