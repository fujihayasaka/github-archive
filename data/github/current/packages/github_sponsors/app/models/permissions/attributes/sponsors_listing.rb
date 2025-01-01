# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class SponsorsListing < Default
      def subject_attributes
        super.merge(
          "subject.owner.id" => participant.owner_id,
          "subject.visibility" => participant.approved? ? "public" : "private",
          "subject.disabled" => participant.disabled?,
        )
      end
    end
  end
end
