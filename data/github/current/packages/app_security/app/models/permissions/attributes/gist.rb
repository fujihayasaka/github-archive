# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Gist < Default
      def subject_attributes
        super.merge(
          # Note that a Gist could not have a user_id, in that case it would be anonymous
          "subject.owner.id" => participant&.user_id,
          "subject.active" => participant&.active?,
        )
      end
    end
  end
end
