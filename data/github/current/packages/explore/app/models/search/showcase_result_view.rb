# typed: true
# frozen_string_literal: true

require "geo_pattern"

module Search
  # A "presenter" class that wraps up a showcase search result. It provides
  # methods for accessing the search highlighted title and blog post body.
  #
  class ShowcaseResultView
    attr_reader :id, :name, :body, :published, :created_at, :updated_at, :slug

    # Create a new showcase result view from the data hash returned from the
    # ElasticSearch showcase index.
    #
    # hash - The Hash of data returned from ElasticSearch
    #
    def initialize(hash)
      source = hash["_source"]

      @id         = hash["_id"]
      @name       = source["name"]
      @slug       = source["slug"]
      @body       = source["body"].to_s
      @published  = source["published"]
      @created_at = Time.parse(source["created_at"])
      @updated_at = Time.parse(source["updated_at"])

      @highlights = hash["highlight"]
    end

    # Convert this view to a params list for URL generation.
    #
    def to_param
      slug
    end

    def geo_pattern
      GeoPattern.generate(@name, { base_color: "#C44040" }).to_data_uri
    end

    alias :published? :published

    # Returns true if this collection is a draft.
    #
    def draft?
      !@published
    end

    alias :body_text :body

    # Returns the search highlighted showcase collection title. If the collection name
    # contains matching search terms, they will be surrounded by `<em>` tags
    # for highlighting.
    #
    # If the name did not contain any matching search terms, then the whole
    # name will be returned.
    #
    # In either case, the text has already been HTML escaped and `html_safe`ed
    # so it's ready to use.
    #
    # This data is GitHub controlled content and no user content is
    # contained in the highlights string.
    #
    # Example
    #
    #   <%= collection.hl_name %>
    #
    # Returns an HTML safe post name.
    #
    def hl_name
      return @hl_name if defined? @hl_name
      @hl_name =
          if @highlights && @highlights["name"]
            @highlights["name"].first
          else
            ERB::Util.force_escape(@name)
          end
    end

    # Returns the search highlighted collection body fragment. If the collection body
    # contains matching search terms, they will be surrounded by `<em>` tags
    # for highlighting.
    #
    # If the body did not contain any matching search terms, then the first
    # 160 words of the body will be returned.
    #
    # In either case, the text has already been HTML escaped and `html_safe`ed
    # so it's ready to use.
    #
    # This data is GitHub controlled content and no user content is
    # contained in the highlights string.
    #
    # Example
    #
    #   <%= collection.hl_body %>
    #
    # Returns an HTML safe body fragment.
    #
    def hl_body
      return @hl_body if defined? @hl_body
      @hl_body =
          if @highlights && @highlights["body"]
            @highlights["body"].first
          else
            EscapeUtils.escape_html(@body).split(" ").slice(0, 160).join(" ").html_safe # rubocop:disable Rails/OutputSafety
          end
    end
  end  # ShowcaseResultView
end  # Search
