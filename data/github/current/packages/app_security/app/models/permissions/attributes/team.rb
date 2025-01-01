# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Team < Default
      def subject_attributes
        super.merge(
          "subject.owner.id" => participant.owner.id,
          "subject.organization.team_discussions_allowed" => participant.organization.team_discussions_allowed?,
          "subject.organization.enhanced_team_posts_enabled" => false,
          "subject.team_post_creation_restricted" => false,
          "subject.business.id" => participant&.owner&.async_business&.sync&.id,
        )
      end
    end
  end
end
