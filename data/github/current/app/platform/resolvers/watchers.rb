# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Watchers < Resolvers::Users
      def resolve
        context[:permission].async_can_get_full_repo?(object).then do |can_get_full_repo|
          if can_get_full_repo
            Helpers::WatchersQuery.new(object, viewer: context[:viewer])
          else
            ArrayWrapper.new([])
          end
        end
      end
    end
  end
end
