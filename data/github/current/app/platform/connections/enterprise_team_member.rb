# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class EnterpriseTeamMember < Connections::Base
      total_count_field

      def total_count
        builder = ::Team::Membership::ScopeBuilder.new(
          team_id: parent.id,
          viewer: context[:viewer],
          query: @object.arguments[:query],
          with_business_teams: true,
        )
        builder.count
      end
    end
  end
end
