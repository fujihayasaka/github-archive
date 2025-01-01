# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class GistComment < Default
      def subject_attributes
        super.merge(
          # Note that a Gist could not have a user_id, in that case it would be anonymous
          "subject.owner.id" => participant&.gist&.user_id,
        )
      end
    end
  end
end
