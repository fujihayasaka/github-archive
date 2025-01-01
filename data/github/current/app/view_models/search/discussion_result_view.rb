# typed: true
# frozen_string_literal: true

module Search
  class DiscussionResultView
    include EscapeHelper

    attr_reader :created, :updated, :comments, :score

    sig { returns String }
    attr_reader :title, :body

    sig { returns Integer }
    attr_reader :id, :num_comments, :number, :repo_id, :user_id

    sig { returns T::Boolean }
    attr_reader :public

    sig { returns T.nilable(Repository) }
    attr_reader :repo

    sig { returns Discussion }
    attr_reader :discussion

    alias :public? :public

    # Max body length
    FRAGMENT_SIZE = ::Search::Queries::DiscussionQuery::FRAGMENT_SIZE

    # Create a new DiscussionResultView from a `discussion` document hash returned from
    # the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    sig { params(hash: T::Hash[String, T.untyped]).void }
    def initialize(hash)
      source = hash["_source"]

      @id = hash["_id"]
      @discussion = T.let(hash["_model"], Discussion)
      @repo = discussion.repository

      @title = source["title"]
      @body = source["body"]
      @number = source["number"]
      @public = source["public"]
      @repo_id = source["repo_id"]
      @user_id = source["user_id"]
      @score = source["score"]
      @comments = source["comments"]
      @num_comments = source["num_comments"]
      @created = Time.parse(source["created_at"])
      @updated = Time.parse(source["updated_at"])
      @highlights = hash["highlight"]
    end

    # Lookup the User object based on the `user_id` of the discussion. Returns
    # the ghost user if the user has deleted their account.
    #
    # Returns the User who authored this discussion (or the ghost User)
    sig { returns User }
    def user
      return @user if defined? @user
      @user = User.find_by(id: @user_id) || User.ghost
    end

    # Returns the user's login String.
    sig { returns String }
    def user_login
      user.display_login
    end

    # Returns true if the discussion has comments.
    sig { returns T::Boolean }
    def comments?
      !@comments.blank?
    end

    # Returns the `name_with_owner` String for the repository that owns the
    # discussion.
    sig { returns T.nilable(String) }
    def name_with_owner
      repo&.name_with_display_owner
    end

    # Returns the `login` of the owner of the discussion's repository.
    sig { returns T.nilable(String) }
    def repository_owner
      repo&.owner_display_login
    end

    # Returns the name of the discussion's repository.
    sig { returns T.nilable(String) }
    def repository_name
      repo&.name
    end

    sig { returns T.nilable(String) }
    def visibility
      repo&.visibility
    end

    # Constructs a URL for linking to the discussion.
    #
    # Returns a relative url String.
    sig { returns String }
    def url
      "/#{repo&.name_with_display_owner}/discussions/#{number}"
    end

    # Returns true if there are highlight fragments for this discussion. The
    # highlight fragments contain text from the various discussion fields with the
    # relevant search terms surrounded by <em> tags.
    sig { returns T::Boolean }
    def highlights?
      !@highlights.nil?
    end

    # Return the discussion title. The title may or may not contain highlight tags,
    # but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped title String.
    sig { returns String }
    def hl_title
      return @hl_title if defined? @hl_title
      @hl_title =
          if highlights? && @highlights.key?("title")
            @highlights["title"].first
          else
            ERB::Util.force_escape(@title)
          end
    end

    # Returns a highlighted text fragment to be displayed along with the other
    # pertinent discussion information. The highlighted text will either be from
    # the discussion body or from the discussion comments (if the body contains no
    # highlighted terms).
    #
    # The returned string is already HTML escaped and html_safe.
    #
    # Returns an HTML escaped text String, or nil if nothing is highlighted.
    sig { returns T.nilable(String) }
    def hl_text
      return @hl_text if defined? @hl_text

      @hl_text =
          if highlights? && @highlights.key?("body")
            find_hl_text(@body, @highlights["body"].first)

          elsif highlights? && @highlights.key?("comments.body")
            find_hl_comment
          else
            str = ERB::Util.force_escape(@body)
            if str.length > FRAGMENT_SIZE
              last = str[FRAGMENT_SIZE..-1].index(/\s/).to_i + FRAGMENT_SIZE
              str = str.slice(0, last) + " ..."
            end
            str.html_safe # rubocop:disable Rails/OutputSafety
          end
    end

    sig { returns String }
    def platform_type_name
      "Discussion"
    end

    # Populate the object with data needed by the search react app
    sig { params(user: T.nilable(User)).returns(T.nilable(String)) }
    def populate_results_data(user)
      @url = url
      return if user.nil?
      @user_login = user.display_login
      @user_avatar_url = user.primary_avatar_url(48)

      hl_title

      hl_text
    end

    sig { returns T::Hash[Symbol, T.untyped] }
    def for_frontend_rendering
      {
        body: @body,
        created: @created,
        hl_text: @hl_text,
        hl_title: @hl_title,
        id: @id,
        num_comments: @num_comments,
        number: @number,
        repo: ::Search::ResultsView::repository_for_frontend_rendering(@repo.repository),
        title: @title,
        url: @url,
        updated: @updated,
        user_avatar_url: @user_avatar_url,
        user_id: @user_id,
        user_login: @user_login,
      }
    end

    private

    # Given some normal text and a highlighted fragment from that text, return
    # the fragment with leading and/or trailing ellipsis to indicate it's
    # position in the original text. If the highlighted fragment is not
    # found in the original text then return nil.
    #
    # text      - The original text String.
    # highlight - The highlighted fragment String.
    #
    # Returns a highlighted text fragment.
    sig { params(text: String, highlight: String).returns(T.nilable(String)) }
    def find_hl_text(text, highlight)
      clean_text = ERB::Util.force_escape(text.gsub(/<\/?em>/, ""))
      # EscapeUtils encodes ', but Lucene SimpleHTMLEncoder does not. Convert it back here
      # so the strings match and we can find the highlighted segment.
      clean_text.gsub!("&#39;", "'")
      clean_hl = highlight.gsub(/<\/?em>/, "")

      return highlight if clean_hl == clean_text

      pos = clean_text.index(clean_hl)
      return if pos.nil?

      # beggining of string
      if 0 == pos
        safe_join([highlight, "..."], " ")

      # end of string
      elsif clean_hl.length + pos == clean_text.length
        safe_join(["...", highlight], " ")

      # middle of string
      else
        safe_join(["...", highlight, "..."], " ")
      end
    end

    # Scan through the comment body highlight strings and find the first one
    # we can use for the highlighted text.
    #
    # Returns a comment body highlight fragment if one exists.
    sig { returns T.nilable(String) }
    def find_hl_comment
      rv = T.let(nil, T.nilable(String))

      @highlights["comments.body"].each do |highlight|
        @comments.each do |comment|
          text = comment["body"]
          rv = find_hl_text(text, highlight)
          break unless rv.nil?
        end

        break unless rv.nil?
      end

      rv
    end
  end  # DiscussionResultView
end  # Search
