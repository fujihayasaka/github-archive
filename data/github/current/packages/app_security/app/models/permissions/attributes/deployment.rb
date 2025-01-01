# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Deployment < Default
      def subject_attributes
        super.merge(
          "subject.repository.id"          => participant.repository_id,
          "subject.repository.owner.id"    => participant.repository&.owner_id,
          "subject.owning_organization.id" => participant.repository&.owning_organization_id,
        )
      end
    end
  end
end
