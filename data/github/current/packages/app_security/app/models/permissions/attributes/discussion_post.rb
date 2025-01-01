# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class DiscussionPost < Default
      def subject_attributes
        super.merge(
          "subject.private"      => participant.private?,
          "subject.team.id"      => participant.team_id,
          "subject.team.privacy" => ::Team.privacies[participant.team&.privacy],
          "subject.owner.id"     => participant.team&.organization_id,
          "subject.business.id"  => participant.team&.organization&.async_business&.sync&.id,
        )
      end
    end
  end
end
