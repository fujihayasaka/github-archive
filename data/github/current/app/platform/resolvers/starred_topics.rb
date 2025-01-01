# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class StarredTopics < Resolvers::Base
      type Connections::StarredTopic, null: true

      def resolve
        if @object.private_profile_for?(@context[:viewer])
          ArrayWrapper.new([])
        else
          object.stars.topics
        end
      end
    end
  end
end
