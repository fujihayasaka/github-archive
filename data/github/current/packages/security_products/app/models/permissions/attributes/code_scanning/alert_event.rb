# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    module CodeScanning
      class AlertEvent < Default
        def subject_attributes
          super.merge(
            "subject.repository.id"          => participant.repository.id,
            "subject.organization.id"        => participant.repository.organization_id,
            "subject.owning_organization.id" => participant.repository.organization_id,
            "subject.business.id"            => participant.repository.organization&.async_business&.sync&.id,
          )
        end
      end
    end
  end
end
