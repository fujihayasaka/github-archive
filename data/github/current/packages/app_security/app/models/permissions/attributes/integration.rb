# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Integration < Default
      def subject_attributes
        super.merge(
          "subject.owner.id" => participant.owner.id,
        )
      end
    end
  end
end
