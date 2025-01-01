# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      class MemberSearchPayload
        include GitHub::Memoizer
        include UrlHelpers
        include AvatarHelper
        include ViewModelHelper

        PER_PAGE = 10

        sig { returns(::Organization) }
        attr_reader :organization

        sig { returns(ActionController::Parameters) }
        attr_reader :params

        sig { returns(::User) }
        attr_reader :current_user

        sig { params(organization: ::Organization, params: ActionController::Parameters, current_user: ::User).void }
        def initialize(organization:, params:, current_user:)
          @organization = organization
          @params = params
          @current_user = current_user
        end

        sig { returns(Copilot::Types::SearchAssignablesPayload) }
        def call
          { total: all_assignables.count, assignables: results }
        end

        private

        sig do
          returns(T::Array[T.any(Copilot::Types::SearchUserPayload,
                                 Copilot::Types::SearchTeamPayload,
                                 Copilot::Types::SearchInvitePayload)])
        end
        memoize def results
          if query.present?
            res = raw_results.select do |result|
              if result[:type] == Copilot::Types::Search::Team
                result[:name].downcase.include?(query)
              else
                result[:display_login].downcase.include?(query)
              end
            end

            res = search if res.empty?
          end

          res || raw_results
        end

        sig do
          returns(T::Array[T.any(Copilot::Types::SearchUserPayload,
                                 Copilot::Types::SearchTeamPayload,
                                 Copilot::Types::SearchInvitePayload)])
        end
        memoize def raw_results
          paged_assignables.map do |assignable|
            if assignable.is_a?(::User)
              user_payload(assignable, true)
            elsif assignable.is_a?(Team)
              team_payload(assignable, true)
            elsif assignable.is_a?(OrganizationInvitation)
              next nil if licenses[:invite_user_ids].include?(assignable.invitee_id)
              next nil if licenses[:invite_emails].include?(assignable.email)
              email_invite_payload(assignable)
            end
          end.compact
        end

        sig do
          returns(T::Array[T.any(::User, Team, OrganizationInvitation)])
        end
        def paged_assignables
          all_assignables.slice(((params[:page] || 1).to_i - 1) * PER_PAGE, PER_PAGE) || []
        end

        sig do
          returns(T::Array[T.any(::User, Team, OrganizationInvitation)])
        end
        def all_assignables
          assignables = teams + members + invites
          sort_assignables!(assignables)
          assignables
        end

        sig { returns(T::Array[::User]) }
        def members
          organization.members.where(suspended_at: nil).where.not(id: licenses[:user_ids]).records
        end

        sig { returns(T::Array[::Team]) }
        def teams
          organization.teams.where.not(id: licenses[:team_ids]).records
        end

        sig { returns(T::Array[::OrganizationInvitation]) }
        def invites
          OrganizationInvitation.pending.where(id: organization.invitation_ids).includes(invitee: :profile).records
        end

        sig { returns(Copilot::Types::CopilotLicenseIdentifiers) }
        def licenses
          copilot_organization.all_copilot_seats_and_assignments_by_type_and_identifier
        end

        sig { params(assignables: T::Array[T.any(Team, ::User, OrganizationInvitation)]).void }
        def sort_assignables!(assignables)
          sort_query = Copilot::SeatManagement::SeatQuery.generate(params)

          if sort_query.sort == :sortable_name
            assignables.sort_by! do |assignable|
              case assignable
              when Team
                assignable.name.to_s.downcase
              when ::User
                assignable.display_login.downcase
              when OrganizationInvitation
                assignable.email_or_invitee_name.downcase
              end
            end

            assignables.reverse! if sort_query.direction == :desc
          elsif sort_query.sort == :requested_at
            requested_users, non_requested_assignables = assignables.partition { |a| a.is_a?(::User) && member_feature_request_mapping.key?(T.must(a.id)) }
            requested_users.sort_by! { |user| member_feature_request_mapping.dig(user.id, :requested_at) }

            requested_users.reverse! if sort_query.direction == :desc
            assignables.replace(requested_users + non_requested_assignables)
          end
        end

        sig { returns(Copilot::Types::SearchAssignables) }
        def search
          search_results = suggestions_view.suggestions.compact.map do |result|
            should_include = copilot_organization.on_free_trial? ? suggestions_view.org_member?(result) : true

            if result.is_a?(::User)
              next if licenses[:user_ids].include?(result.id)
              next unless should_include
              next if result.suspended?
              user_payload(result, suggestions_view.org_member?(result))
            elsif result.is_a?(Team)
              next if licenses[:team_ids].include?(result.id)
              team_payload(result, true)
            end
          end.compact


          if search_results.empty? && ::User.valid_email?(params[:q]) && !copilot_organization.on_free_trial? && !licenses[:invite_emails].include?(params[:q])
            search_results << email_invite_payload(params[:q])
          end

          search_results
        end

        sig { returns(Copilot::SeatManagement::UserSuggestionsView) }
        memoize def suggestions_view
          create_view_model(Copilot::SeatManagement::UserSuggestionsView,
            organization: organization,
            query: params[:q],
            include_teams: true
          )
        end

        sig { returns(T.nilable(String)) }
        memoize def query
          params[:q]&.downcase
        end

        sig { returns(T::Hash[Integer, ::Team]) }
        def teams_hash
          teams.index_by(&:id)
        end

        sig { returns(Copilot::Organization) }
        memoize def copilot_organization
          Copilot::Organization.new(@organization)
        end

        sig { params(user: ::User, org_member: T::Boolean).returns(Copilot::Types::SearchUserPayload) }
        def user_payload(user, org_member)
          {
            id: user.id,
            avatar_url: avatar_url_for(user, 24),
            display_login: user.display_login,
            profile_name: user.profile_name,
            org_member: org_member,
            type: Copilot::Types::Search::User,
            feature_request: member_feature_request_mapping[T.must(user.id)]
          }
        end

        sig { params(team: Team, org_member: T::Boolean).returns(Copilot::Types::SearchTeamPayload) }
        def team_payload(team, org_member)
          {
            id: team.id,
            avatar_url: avatar_url_for(team, 24),
            name: team.name,
            slug: T.must(team.slug),
            org_member: org_member,
            member_ids: team.member_ids,
            type: Copilot::Types::Search::Team
          }
        end

        sig { params(invitation: T.any(OrganizationInvitation, String)).returns(Copilot::Types::SearchInvitePayload) }
        def email_invite_payload(invitation)
          if invitation.is_a?(String)
            return {
              id: nil,
              avatar_url: nil,
              org_member: false,
              type: Copilot::Types::Search::OrganizationInvite,
              display_login: invitation,
              profile_name: nil
            }
          end

          {
            org_member: false,
            type: Copilot::Types::Search::OrganizationInvite,
            id: invitation.id,
            avatar_url: invitation.invitee.nil? ? nil : avatar_url_for(invitation.invitee, 24),
            # This field doesnt map to the potential display_login of the underlying invitee,
            # but occupies the same visual precedence a display_login would when showing
            # information about a user object in the UI.
            display_login: invitation.email_or_invitee_name,
            # This is confusing, but matches the existing organization invite behavior.
            # In other places we display these entities, the profile name is shown where the display_login
            # might be shown in other scenarios.
            profile_name: invitation.invitee&.display_login
          }
        end

        sig { returns(T::Hash[Integer, Copilot::Types::MemberFeatureRequest]) }
        memoize def member_feature_request_mapping
          with_database_error_fallback(fallback: {}) do
            MemberFeatureRequest
              .requested
              .where(organization: organization, feature: MemberFeatureRequest::Feature::CopilotForBusiness)
              .pluck(:requester_id, :id, :updated_at)
              .map { |requester_id, id, updated_at| [requester_id, { id: id, requested_at: updated_at }] }
              .to_h
          end
        end

        # This is just to please create_view_model. We don't need a user session
        sig { returns({}) }
        def user_session = {}
      end
    end
  end
end
