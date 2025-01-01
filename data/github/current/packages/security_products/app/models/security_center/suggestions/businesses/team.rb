# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class Team < Base
        extend T::Sig

        sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs
        sig { returns(User) }; attr_reader :user
        sig { returns(T::Boolean) }; attr_reader :skip_limit

        sig { params(authorized_orgs: T::Array[Organization], user: User, skip_limit: T::Boolean, kwargs: T.untyped).void }
        def initialize(authorized_orgs:, user:, skip_limit: false, **kwargs)
          super(**T.unsafe(kwargs))
          @authorized_orgs = authorized_orgs
          @user = user

          # The Teams multi-select dropdown does not re-fetch new results as the user scrolls or filters.
          # Therefore, all Teams must be fetched.
          @skip_limit = skip_limit
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if authorized_orgs.blank?

          # If `value` is of the form "org/team", then match "team" to teams in that org only.
          #
          # If `value` does not have a "/", we don't know if the user is looking for orgs or teams.
          # Therefore, find all orgs OR teams matching `value`.
          team_rel =
            if value.include?("/")
              org_and_team_suggestions_rel
            else
              org_or_team_suggestions_rel
            end

          orgs_by_id = authorized_orgs.index_by(&:id)
          team_rel = without_selected_values_rel(team_rel)
            .order(:name, :id)
            .then { |rel| skip_limit ? rel : rel.limit(limit) }
            .pluck(:name, :slug, :organization_id)

          team_rel.map do |team_name, team_slug, org_id|
            org_display_login = orgs_by_id[org_id].display_login
            Suggestion.new(
              description: "#{org_display_login}/#{team_slug}",
              label: team_name,
              value: "#{org_display_login}/#{team_slug}",
            )
          end
        end

        private

        sig { returns(ActiveRecord::Relation) }
        def all_teams_accessible_to_user_rel
          return ::Team.none if authorized_orgs.blank?

          # Split the orgs into adminable and member orgs
          organization_ids = authorized_orgs.map(&:id)
          user_abilities = user.abilities(ids: organization_ids, types: "Organization")
          adminable_org_ids = user_abilities.select { |ability| ability.admin? }.map(&:subject_id)
          member_org_ids = user_abilities.reject { |ability| ability.admin? }.map(&:subject_id)

          # Get all teams where
          #  - the user is an admin of the owning org
          #  - the user is an admin/maintainer of the team
          #  - the team is public in one of the orgs
          team_rel = ::Team.where(organization_id: adminable_org_ids)
            .or(user.teams.where(organization_id: member_org_ids))
            .or(::Team.where(organization_id: member_org_ids).with_minimum_privacy(:closed).where(deleted: false))

          team_rel
        end

        sig { returns(ActiveRecord::Relation) }
        def org_and_team_suggestions_rel
          org_name, team_name = value.split("/", 2)
          orgs = authorized_orgs.select { |o| o.display_login == org_name }
          return ::Team.none if orgs.blank?

          rel = all_teams_accessible_to_user_rel.where(organization_id: orgs.pluck(:id))
          rel = rel.where("slug LIKE ?", "%#{team_name}%") if team_name.present?
          rel
        end

        sig { returns(ActiveRecord::Relation) }
        def org_or_team_suggestions_rel
          rel = all_teams_accessible_to_user_rel
          return rel if value.blank?

          repo_suggestions = rel.where("slug LIKE ?", "%#{value}%")
          orgs = authorized_orgs.select { |o| o.display_login.include?(value) }
          org_suggestions = rel.where(organization_id: orgs.pluck(:id))

          org_suggestions.or(repo_suggestions)
        end

        sig { params(team_rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def without_selected_values_rel(team_rel)
          new_team_rel = team_rel

          selected_values.each do |selected_value|
            org_name, team_name = selected_value.split("/", 2)
            next if org_name.blank? && team_name.blank?

            org = authorized_orgs.find { |o| o.display_login == org_name }
            next if org.blank?

            new_team_rel = T.cast(new_team_rel.where.not(organization_id: org.id, slug: team_name), ActiveRecord::Relation)
          end

          new_team_rel
        end
      end
    end
  end
end
