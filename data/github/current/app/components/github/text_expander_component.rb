# typed: true
# frozen_string_literal: true

module GitHub
  class TextExpanderComponent < ApplicationComponent
    include CommentSuggestionsHelper

    attr_reader :emoji, :issue, :keys, :mention, :repository, :user

    # Render a text-expander element. By default, it provides emoji suggestions. To
    # enable mention or issue suggestions, pass a repository and user.
    #
    # ==== Options
    # * <tt>:emoji</tt> - When set to false, disables emoji suggestions.
    # * <tt>:mention</tt> - When set to true, enables mentions. Requires a repository and user.
    # * <tt>:issue</tt> - When set to true, enables issue suggestions. Requires a repository and user.
    # * <tt>:repository</tt> - Required when `mention:` or `issue:` set to true. Used to scope suggestions.
    # * <tt>:user</tt> - Required when `mention:` or `issue:` set to true. Used to scope suggestions.
    #
    # ==== Examples
    #
    #    TextExpanderComponent.new
    #    TextExpanderComponent.new(mention: true, repository: repo, user: current_user)
    #    TextExpanderComponent.new(issue: true, repository: repo, user: current_user)
    def initialize(emoji: true, mention: false, issue: false, repository: nil, user: nil)
      if (mention || issue) && (repository.nil? || user.nil?)
        raise ArgumentError.new("Must provide repository and user when mention or issue expansion is enabled.")
      end

      @repository = repository
      @user = user
      @emoji = emoji
      @mention = mention
      @issue = issue
      @keys = []

      keys << ":" if emoji
      keys << "@" if mention
      keys << "#" if issue
    end

    def call
      content_tag("text-expander", content, keys: keys.join(" "), data: data)
    end

    def data
      data = {}
      data[:emoji_url] = emoji_suggestions_path if emoji
      data[:mention_url] = mention_url if mention
      data[:issue_url] = issue_url if issue
      data
    end

    def mention_url
      suggestions_path(mention_suggestions_params(repository, user))
    end

    def issue_url
      suggestions_path(user_id: user, repository: repository, issue_suggester: "1")
    end
  end
end
