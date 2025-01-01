# typed: true
# frozen_string_literal: true

module Organization::HovercardDependency
  extend ActiveSupport::Concern
  include UserHovercard::SubjectDefinition
  extend T::Helpers

  requires_ancestor { Organization }

  def user_hovercard_parent
  end

  included do
    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :teams, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Organization)

      next if user.private_profile_for?(viewer)
      next unless member?(user)

      user_team_ids = user.teams.where(organization_id: id).pluck(:id)
      visible_teams = visible_teams_for(viewer).where(id: user_team_ids)
      next if visible_teams.empty?

      UserHovercard::Contexts::OrganizationTeams.new(user: user, all: visible_teams, organization: self)
    end
    # rubocop:enable Lint/UnusedBlockArgument

    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :blocks, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Organization)

      if adminable_by?(viewer) && blocking?(user)
        UserHovercard::Contexts::Blocks.new(
          blocked_by_viewer: user.blocked_by?(viewer),
          blocking_org: self
        )
      end
    end
    # rubocop:enable Lint/UnusedBlockArgument
  end
end
