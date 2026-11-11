# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class WorkflowRun < Default
      def subject_attributes
        super.merge(
          "subject.repository.public"      => participant.repository.public?,
          "subject.repository.id"          => participant.repository_id,
          "subject.repository.owner.id"    => participant.repository&.owner_id,
          "subject.repository.internal"    => participant.repository.internal?,
          "subject.owning_organization.id" => participant.repository&.owning_organization_id,
          "subject.business.id"            => participant.repository.owner&.async_business&.sync&.id,
          "subject.organization.id"        => participant.repository.owner&.organization? ? participant.repository.owner_id : nil,
        )
      end
    end
  end
end
