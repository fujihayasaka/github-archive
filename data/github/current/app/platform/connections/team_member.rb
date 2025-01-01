# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class TeamMember < Connections::Base
      total_count_field

      def total_count
        builder = ::Team::Membership::ScopeBuilder.new(
          team_id: parent.id,
          viewer: context[:viewer],
          role: @object.arguments[:role],
          membership: @object.arguments[:membership],
          query: @object.arguments[:query],
        )
        builder.count
      end
    end
  end
end
