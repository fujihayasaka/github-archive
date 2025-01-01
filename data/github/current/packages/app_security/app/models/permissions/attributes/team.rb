# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Team < Default
      def subject_attributes
        super.merge(
          "subject.owner.id" => participant.owner.id,
          "subject.organization.team_discussions_allowed" => participant.organization.team_discussions_allowed?,
          "subject.organization.enhanced_team_posts_enabled" => GitHub.flipper[:enhanced_team_posts].enabled?(participant.organization),
          "subject.team_post_creation_restricted" => participant.team_post_creation_disabled?
        )
      end
    end
  end
end
