# typed: true
# frozen_string_literal: true

module Api::Serializer
  module TextMatch
    include Kernel
    # Public: Serialize the given arguments into a 'text_match' Hash (i.e., a
    # Hash that conforms to the 'text_match' schema.
    #
    # search_result - The Hash containing a single search result.
    # field_name    - The String name of the highlighted field (i.e., the field
    #                 whose text matched the search query).
    # highlights    - The Hash describing highlights for the field.
    #                 :text    - The String containing a fragment of text
    #                            representing a search hit.
    #                 :indices - The Array of Integers representing start/end
    #                            index pairs.
    #
    # Returns the Hash, or nil if the search result type or the field name is
    # unrecognized.
    def self.to_hash(search_result, field_name, highlights)
      match = TextMatch.for(search_result, field_name, highlights)
      match.nil? ? nil : match.to_hash
    end

    # Internal: Return an object capable of serializing the given arguments to
    # a 'text_match' Hash (i.e., a Hash that conforms to the 'text_match'
    # schema).
    #
    # The returned object responds to +to_hash+, which will produce the
    # serialized Hash.
    #
    # Returns an object capabale of serializing the given field, or nil if the
    # search result type or the field name is unrecognized.
    def self.for(search_result, field_name, highlights)
      index_name = Elastomer.get_index_name_from_result(search_result)
      klass = class_for(index_name, field_name)

      return nil if klass.nil?

      klass.new(search_result, field_name, highlights)
    end

    # Internal
    def self.class_for(object_type, field_name)
      classes_for_object_type =
        case object_type
        when "code-search"                  then [Api::Serializer::FileContentTextMatch]
        when "commits"                      then [Api::Serializer::CommitMessageTextMatch]
        when "issues", "pull-requests"      then [Api::Serializer::IssueTextMatch, Api::Serializer::IssueCommentishTextMatch]
        when "labels"                       then [Api::Serializer::LabelTextMatch]
        when "repos"                        then [Api::Serializer::RepositoryTextMatch]
        when "topics"                       then [Api::Serializer::TopicTextMatch]
        when "users"                        then [Api::Serializer::UserTextMatch]
        end

      classes_for_object_type&.find do |klass|
        klass.supported_field_names.include?(field_name)
      end
    end

    attr_reader :search_result, :field_name, :text, :indices

    def initialize(search_result, field_name, matching_text_and_indices)
      @search_result = search_result
      @field_name = field_name
      @text = matching_text_and_indices[:text]
      @indices = matching_text_and_indices[:indices]
    end

    def to_hash
      {
        object_url: object_url,
        object_type: object_type,
        property: property,
        fragment: text,
        matches: matches(text, indices),
      }
    end

    # Internal
    def object_url
      Api::Serializer.url(object_url_suffix)
    end

    # Internal
    def object_url_suffix
      raise NotImplementedError
    end

    # Internal
    def object_type
      raise NotImplementedError
    end

    # Internal
    def property
      raise NotImplementedError
    end

    # Internal: Serialize a collection of text matches and indices in the
    # appropriate format for use in a JSON response.
    #
    # text    - The String containing a fragment of text representing a search
    #           hit.
    # indices - The Array of Integers representing start/end index pairs.
    #
    # Examples
    #
    #   matches('foo bar foo baz quux', [0, 3, 8, 11, 16, 20])
    #   # => [
    #   #      { :text => 'foo', :indices => [0, 3] },
    #   #      { :text => 'foo', :indices => [8, 11] },
    #   #      { :text => 'quux', :indices => [16, 20] },
    #   #    ]
    #
    #   If the indices array contains just one index, it is assumed to be a match at the end of the text.
    #
    # Returns the Array of Hashes.
    def matches(text, indices)
      start_and_end_index_pairs = indices.length == 1 ? [indices[0], text.length].each_slice(2) : indices.each_slice(2)
      ary = start_and_end_index_pairs.map do |start_index, end_index|
        if start_index && end_index
          match_length = end_index - start_index
          {
            text: text.slice(start_index, match_length),
            indices: [start_index, end_index],
          }
        end
      end
      ary.compact!
      ary
    end
  end
end
