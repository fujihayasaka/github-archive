# typed: true
# frozen_string_literal: true

module Search
  class WikiResultView
    include EscapeHelper

    FRAGMENT_SIZE = Search::Queries::WikiQuery::FRAGMENT_SIZE

    attr_reader :id, :title, :path, :filename, :format, :body, :public,
                :updated_at, :repo, :page

    # Create a new WikiResultView from a `page` document hash returned from
    # the Elasticsearch index.
    #
    # hash - Document Hash returned by Elasticsearch
    #
    def initialize(hash)
      source = hash["_source"]

      @id = hash["_id"]
      # This depends on setting the repo on the hash in prune_results, which is
      # a terrible implicit dependency to have. If it's necessary it will have
      # to be made more explicit.
      @repo = hash["_model"]

      @title       = source["title"]
      @path        = source["path"]
      @filename    = source["filename"]
      @format      = source["format"]
      @body        = source["body"] || ""
      @public      = source["public"]
      @repo_id     = source["repo_id"]
      @updated_at  = Time.parse(source["updated_at"])

      @highlights  = hash["highlight"]

      @page        = GitHub::Unsullied::Page.new(@repo.unsullied_wiki, { "path" => @path })
    end

    def name_with_owner
      repo.name_with_display_owner
    end

    def repo_owner
      repo.owner
    end

    def owner_login
      repo_owner.display_login
    end

    # Return the page title. The title may or may not contain highlight tags,
    # but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML-safe String.
    def hl_title
      return @hl_title if defined? @hl_title
      @hl_title =
          if @highlights && @highlights.key?("title")
            @highlights["title"].first
          else
            ERB::Util.force_escape(@title)
          end
    end

    # Returns a highlighted body fragment. If there are no body highlights,
    # return an unhighlighted snippet of the body.
    #
    # Returns an HTML-safe String.
    def hl_body
      return @hl_body if defined? @hl_body

      @hl_body =
        if @highlights && @highlights.key?("body")
          find_hl_text(@body, @highlights["body"].first)
        else
          elided_text(@body)
        end
    end

    # Internal: Cut down a text string to the fragment size, eliding on
    # whitespace if possible.
    #
    # Returns a string suffixed with an ellipsis.
    def elided_text(text)
      str = ERB::Util.force_escape(text)
      if str.length > FRAGMENT_SIZE
        last = str[FRAGMENT_SIZE..-1].index(/\s/).to_i + FRAGMENT_SIZE
        str = str.slice(0, last) + " ..."
      end
      str.html_safe # rubocop:disable Rails/OutputSafety
    end

    # Given some normal text and a highlighted fragment from that text, return
    # the fragment with leading and/or trailing ellipsis to indicate its
    # position in the original text. If the highlighted fragment is not
    # found in the original text then return nil.
    #
    # text      - The original text String.
    # highlight - The highlighted fragment String.
    #
    # Returns a highlighted text fragment.
    def find_hl_text(text, highlight)
      clean_text = ERB::Util.force_escape(text.gsub(/<\/?em>/, ""))
      clean_hl = ERB::Util.force_escape(highlight.gsub(/<\/?em>/, ""))

      return highlight if clean_hl == clean_text

      pos = clean_text.index(clean_hl)
      # If pos is nil, we couldn't find the highlight in the text. This probably
      # means there was an escaped character in the text. Just return the
      # highlight without ellipses.
      return highlight unless pos

      # beginning of string
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

    def private_public_class
      public ? "wiki-list-item-public" : "wiki-list-item-private"
    end

    def populate_results_data
      hl_body
      hl_title
    end

    def for_frontend_rendering
      {
        body: @body,
        filename: @filename,
        format: @format,
        hl_body: @hl_body,
        hl_title: @hl_title,
        id: @id,
        path: @path,
        public: @public,
        repo: ::Search::ResultsView::repository_for_frontend_rendering(@repo),
        repo_id: @repo_id,
        title: @title,
        updated_at: @updated_at
      }
    end
  end
end
