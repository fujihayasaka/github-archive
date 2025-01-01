# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class MemexProject < Default
      def subject_attributes
        super.merge(
          "subject.creator.id"             => participant.creator_id,
          "subject.public"                 => participant.public,
          "subject.memex_project.public"   => participant.public,
          "subject.owner.id"               => participant.owner_id,
          "subject.owner.type"             => participant.owner_type,
        )
      end
    end
  end
end
