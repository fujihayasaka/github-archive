# typed: true
# frozen_string_literal: true

module Search
  # The whole point of this module is to transform the highlighted fragments
  # returned by ElasticSearch.
  #
  # When you request highlights along with the search results, ElasticSearch
  # will attach little fragments of text showing you where a match occurred
  # for a particular result in the result list. These highlighted fragments
  # contain inline tags marking the beginning and the end of the highlighted
  # text.
  #
  # This module will transform the highlighted fragments by removing the
  # inline tags and returning indices instead. These indices mark the
  # beginning and end locations where highlighted text appears in the string.
  #
  module OffsetHighlighter
    extend self
    include Kernel

    # These tags are used to mark highlighted text. These are used to find the
    # indices of the highlighted regions and will be removed. We return the
    # indices instead.
    PRE_TAG  = "\x1e\x1f".freeze
    POST_TAG = "\x1f\x1e".freeze

    ESCAPED_PRE_TAG  = Regexp.escape(PRE_TAG).freeze
    ESCAPED_POST_TAG = Regexp.escape(POST_TAG).freeze

    # These are the default highlighting options.
    DEFAULTS = {
      encoder: :default,
      pre_tags: [PRE_TAG],
      post_tags: [POST_TAG],
    }.freeze

    # Returns the default highlighting options as a Hash.
    def defaults
      DEFAULTS
    end

    # When we get highlighted fragments back from ElasticSearch they contain
    # highlighting tags inline with the text. The purpose of this method is to
    # strip out those tags and return offset locations instead marking where
    # the highlights occur in the strings.
    #
    # So given a highlight Hash from an ElasticSearch search result, this
    # method will iterate over each field in the hash and transform the inline
    # highlighting into offset markers.
    #
    # highlight - A Hash of field highlight values
    #
    # Returns the highlight Hash.
    def transform(highlight)
      return if highlight.nil?

      highlight.each do |_key, ary|
        ary.map! { |string| extract_indices(string) }
      end
    end

    # Internal: Given a string that contains highlighting tags, this method
    # will remove the tags from the string and return the highlight offset
    # locations instead.
    #
    # The indices are given in pairs marking the first highlighted letter and
    # just after the last highlighted letter. The indices are given this way
    # so you can easily call `insert(offset, "<tag>")` on the string to insert
    # the highlighting tags again. Just remember to work in reverse order so
    # you don't destroy later offset locations.
    #
    # string - A String containing highlighting tags
    #
    # Examples
    #
    #   extract_indices( "foo <tag>bar</tag> baz <tag>buz</tag>" )
    #   # => {
    #     :text    => "foo bar baz buz",
    #     :indices => [4, 7, 12, 15]
    #   }
    #
    # Returns a Hash containing the :text and the highlight :indices
    def extract_indices(string)
      indices = []
      pre = T.let(true, T::Boolean)

      # get rid of silly post/pre tags that follow one right after the other
      # with only whitespace between them
      string = string.gsub(/#{ESCAPED_POST_TAG}(\s*)#{ESCAPED_PRE_TAG}/, '\1')

      loop do
        tag = pre ? PRE_TAG : POST_TAG
        pre = !pre

        index = string.index tag
        break if index.nil?

        indices << index
        string.slice!(index, tag.length)
      end

      { text: string, indices: indices }
    end
  end
end
