# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Organization < Default
      def subject_attributes
        super.merge(
          "subject.business.id" => participant.async_business&.sync&.id,
          "subject.organization.id" => participant.id,
        )
      end
    end
  end
end
