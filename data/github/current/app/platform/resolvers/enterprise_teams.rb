# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseTeams < Resolvers::Base
      type Connections::EnterpriseTeam, null: false

      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::EnterpriseTeamOrder,
        "Ordering options for enterprise teams returned from the connection.",
        required: false, default_value: { field: "id", direction: "ASC" }

      def resolve(query: nil, order_by: nil)
        scope = object.business_teams.includes(:business)  # preload the belongs_to

        if query.present?
          sanitized = ActiveRecord::Base.sanitize_sql_like(query.strip.downcase)
          scope = scope.where("teams.name LIKE ? OR teams.slug LIKE ?", "%#{sanitized}%", "%#{sanitized}%")
        end

        if order_by && ::Team.column_names.include?(order_by[:field])
          unless order_by[:field] == "id" && order_by[:direction].to_s.casecmp("asc").zero?
            scope = scope.order(order_by[:field] => order_by[:direction])
          end
        end

        scope
      end
    end
  end
end
