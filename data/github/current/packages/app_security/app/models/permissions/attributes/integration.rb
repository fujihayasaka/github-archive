# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Integration < Default
      def subject_attributes
        super.merge(
          "subject.owner.id" => participant.owner.id,
          "subject.organization.id" => participant.organization_owned? ? participant.owner.id : nil,
          # We only want to populate subject.business.id when it is organization owned
          "subject.business.id" => participant.organization_owned? ? participant.owner.async_business&.sync&.id : nil
        )
      end
    end
  end
end
