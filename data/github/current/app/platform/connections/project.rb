# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Project < Connections::Base
      description "A list of projects associated with the owner."

      total_count_field

      def total_count
        case @object
        when Platform::ConnectionWrappers::ElasticSearchQuery
          case @object.arguments[:states]
          when ["open"]
            @object.open_count
          when ["closed"]
            @object.closed_count
          else
            @object.total_count
          end
        when Platform::ConnectionWrappers::Relation
          @object.items.count
        else
          0
        end
      end
    end
  end
end
