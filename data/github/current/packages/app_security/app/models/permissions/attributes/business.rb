# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Business < Default
      def subject_attributes
        super.merge(
          "subject.business.id" => participant.id
        )
      end
    end
  end
end
