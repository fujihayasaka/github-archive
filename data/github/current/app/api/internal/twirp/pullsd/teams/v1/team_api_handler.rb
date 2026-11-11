# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-teams"

module Api::Internal::Twirp::Pullsd
  module Teams
    module V1
      # Handler for the MonolithTwirp::Pullsd::Teams::V1::TeamAPIService
      class TeamAPIHandler < Api::Internal::Twirp::Handler
        include Api::Internal::Twirp::Pullsd::Shared::ViewerResolver

        allow_access_for :client, allowed_clients: ["pullsd"]
        handles_service MonolithTwirp::Pullsd::Teams::V1::TeamAPIService

        # Public: Implementation of the ManyById Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Teams::V1::ManyByIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Teams::V1::ManyByIdResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Teams::V1::ManyByIdRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Teams::V1::ManyByIdResponse, Twirp::Error))
        end
        def many_by_id(req, env)
          @current_user = resolve_viewer(
            viewer_id: req.viewer_id,
            installation_id: req.installation_id,
            installation_type: req.installation_type,
            oauth_access_id: req.oauth_access_id,
          )
          return MonolithTwirp::Pullsd::Teams::V1::ManyByIdResponse.new if @current_user.nil?

          team_ids = req.team_ids.to_a
          return MonolithTwirp::Pullsd::Teams::V1::ManyByIdResponse.new if team_ids.empty?

          teams = Orgs.domain.teams.teams_by_ids(team_ids)
          return MonolithTwirp::Pullsd::Teams::V1::ManyByIdResponse.new if teams.empty?

          visible_teams = teams.select { |team| team.is_a?(Team) && team.visible_to?(@current_user) }
          return MonolithTwirp::Pullsd::Teams::V1::ManyByIdResponse.new if visible_teams.empty?

          all_teams = collect_teams_with_parents(visible_teams)

          team_protos = all_teams.map { |team| serialize_team(team, exclude_parent: !team.visible_to?(@current_user)) }
          MonolithTwirp::Pullsd::Teams::V1::ManyByIdResponse.new(teams: team_protos)
        end

        private

        sig { params(teams: T::Array[Orgs::ITeam]).returns(T::Array[Orgs::ITeam]) }
        def collect_teams_with_parents(teams)
          all_teams = teams.dup

          teams.each do |team|
            next unless team.is_a?(Team)

            parent = team.parent_team
            all_teams << parent if parent && parent.visible_to?(@current_user) && !all_teams.include?(parent)
          end

          all_teams
        end

        sig { params(team: Orgs::ITeam, options: T::Hash[Symbol, T.untyped]).returns(MonolithTwirp::Pullsd::Teams::V1::Team) }
        def serialize_team(team, options = {})
          team_hash = Api::Serializer.serialize(:team_hash, team, options)
          description = team_hash&.dig(:description)

          MonolithTwirp::Pullsd::Teams::V1::Team.new(
            id: team.id,
            node_id: team_hash&.dig(:node_id),
            name: team_hash&.dig(:name),
            description: description,
            permission: team_hash&.dig(:permission),
            privacy: team_hash&.dig(:privacy),
            notification_setting: team_hash&.dig(:notification_setting),
            slug: team_hash&.dig(:slug),
            ldap_dn: team_hash&.dig(:ldap_dn),
            type: team_hash&.dig(:type),
            organization_id: team_hash&.dig(:organization_id),
            parent_team_id: team_hash&.dig(:parent)&.dig(:id),
            has_description: !description.nil?
          )
        end
      end
    end
  end
end
