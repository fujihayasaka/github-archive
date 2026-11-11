# typed: true
# frozen_string_literal: true

module Search
  class LabelResultView
    include EscapeHelper

    attr_reader :id, :label, :name, :repository, :created, :updated, :description

    # Create a new LabelResultView from an `label` document hash returned from the ElasticSearch
    # index.
    #
    # hash - Document Hash returned by ElasticSearch
    def initialize(hash)
      source = hash["_source"]

      @id = hash["_id"]
      @label = hash["_model"]
      @repository = @label.repository

      @name = source["name"]
      @description = source["description"]
      @created = Time.parse(source["created_at"])
      @updated = Time.parse(source["updated_at"])

      @highlights = hash["highlight"]
    end

    def color
      @label.color
    end

    # Returns true if there are highlight fragments for this label. The
    # highlight fragments contain text from the various label fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    # Return the label name. The name may or may not contain highlight tags, but either way it has
    # been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped name String.
    def hl_name
      @hl_name ||= if highlights? && @highlights.key?("name")
        @highlights["name"].first
      else
        ERB::Util.force_escape(name)
      end
    end

    # Returns a highlighted description fragment to be displayed along with the other pertinent
    # label information. The returned string is already HTML escaped and html_safe.
    #
    # Returns an HTML escaped text String.
    def hl_description
      return @hl_description if defined? @hl_description

      @hl_description = if highlights? && @highlights.key?("description")
        @highlights["description"].first
      else
        ERB::Util.force_escape(description)
      end
    end
  end
end
