# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class RepositoryLanguage < Edges::Base
      description "Represents the language of a repository."
      graphql_name "LanguageEdge"

      field :cursor, String, null: false

      field :node, Objects::Language, null: false

      def node
        Loaders::ActiveRecord.load(::LanguageName, @object.node.language_name_id)
      end

      field :size, Integer, null: false,
        description: "The number of bytes of code written in the language."

      def size
        @object.node.size
      end
    end
  end
end
