# typed: true
# frozen_string_literal: true

module Search
  class IssueResultView
    include EscapeHelper

    attr_reader :id, :title, :body, :state, :created, :updated, :num_comments,
                :number, :comments, :public, :repo_id, :author_id, :issue,
                :repo, :num_reactions, :reactions
    attr_accessor :other_issues, :labels, :author_name, :author_avatar_url, :reviewable_state, :merged
    alias :public? :public

    # Max body length
    FRAGMENT_SIZE = ::Search::Queries::IssueQuery::FRAGMENT_SIZE

    # Create a new IssueResultView from an `issue` document hash returned from
    # the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    #
    def initialize(hash, viewer = nil)
      source = hash["_source"]

      @id    = hash["_id"]
      @issue = hash["_model"]
      @repo  = issue.repository

      @title     = source["title"]
      @body      = source["body"]
      @state     = source["state"]
      @number    = source["number"]
      @public    = source["public"]
      @repo_id   = source["repo_id"]
      @author_id = source["author_id"]
      @comments  = source["comments"]
      @reactions = source["reactions"]

      @num_comments  = source["num_comments"]
      @num_reactions = source["num_reactions"]

      @created = Time.parse(source["created_at"])
      @updated = Time.parse(source["updated_at"])

      @highlights = hash["highlight"]

      @viewer = viewer

      # Adjust state as necessary
      if issue.pull_request? && issue.pull_request.merged?
        @state = "merged"
      elsif issue.pull_request? && issue.pull_request.draft?
        @state = "draft"
      end
    end

    # Lookup the User object based on the `author_id` of the issue. Returns
    # the ghost user if the author has deleted their account.
    #
    # Returns the User who authored this issue (or the ghost User)
    def author
      return @author if defined? @author
      @author = User.find_by(id: @author_id) || User.ghost
    end

    # Returns the author's login String.
    def author_login
      author.display_login
    end

    # Returns true if the issue is a pull request.
    def pull_request?
      @issue.pull_request?
    end

    # Returns true if the issue has comments.
    def comments?
      !@comments.blank?
    end

    # Returns the `name_with_owner` String for the repository that owns the
    # issue.
    def name_with_owner
      repo.name_with_display_owner
    end

    # Returns the `login` of the owner of the issue's repository.
    def repository_owner
      repo.owner.display_login if repo.owner
    end

    # Returns the name of the issue's repository.
    def repository_name
      repo.name
    end

    # Returns true if the issue is open.
    def open?
      state == "open"
    end

    # Returns true if the issue is closed.
    def closed?
      state == "closed"
    end

    def icon_symbol
      if pull_request?
        "git-pull-request"
      else
        if open?
          "issue-opened"
        elsif @issue&.state_reason_not_planned?
          Issue::StateReasonDependency::OCTICONS[:not_planned][:icon]
        else
          "issue-closed"
        end
      end
    end

    def icon_class
      if @issue&.state_reason_not_planned?
        Issue::StateReasonDependency::OCTICONS[:not_planned][:class]
      else
        state
      end
    end

    def visibility
      repo.visibility
    end

    # Constructs a URL for linking to the issue.
    #
    # Returns a relative url String.
    def url
      "/#{repo.name_with_display_owner}/#{pull_request? ? 'pull' : 'issues'}/#{number}"
    end

    # Returns true if there are highlight fragments for this issue. The
    # highlight fragments contain text from the various issue fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    # Return the issue title. The title may or may not contain highlight tags,
    # but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped title String.
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
    # pertinent issue information. The highlighted text will either be from
    # the issue body or from the issue comments (if the body contains no
    # highlighted terms).
    #
    # The returned string is already HTML escaped and html_safe.
    #
    # Returns an HTML escaped text String.
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

    def platform_type_name
      "Issue"
    end

    def for_frontend_rendering
      {
        author_name: @author_name,
        author_avatar_url: @author_avatar_url,
        id: @id,
        issue: {
          issue: {
            pull_request_id: @issue.pull_request_id
          },
        },
        repo: ::Search::ResultsView::repository_for_frontend_rendering(@repo.repository),
        labels: @labels,
        num_comments: @num_comments,
        number: @number,
        state: @state,
        hl_title: @hl_title,
        hl_text: @hl_text,
        created: @created,
        reviewable_state: @reviewable_state,
        merged: @merged,
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
    # Returns an comment body highlight fragement.
    def find_hl_comment
      rv = T.let(nil, T.untyped)

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
  end  # IssueResultView
end  # Search
