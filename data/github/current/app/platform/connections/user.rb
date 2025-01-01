# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class User < Connections::Base
      description "A list of users."
      total_count_field

      field :total_spammy_count, Integer, null: false, visibility: :internal,
          description: "Identifies the total count of spammy users in the connection."

      def total_spammy_count
        @object.items.spammy.count
      end
    end
  end
end
