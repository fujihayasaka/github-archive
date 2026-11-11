# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class RepositoryLanguage < Connections::Base
      description "A list of languages associated with the parent."
      graphql_name "LanguageConnection"

      total_count_field

      field :total_size, Integer, null: false, description: "The total size in bytes of files written in that language."

      def total_size
        @object.items.sum(:size)
      end

      # custom nodes implementation to support custom language edge
      def nodes
        @object.edge_nodes.then do |nodes|
          Promise.all(nodes.map { |value| Loaders::ActiveRecord.load(::LanguageName, value.language_name_id) })
        end
      end
    end
  end
end
