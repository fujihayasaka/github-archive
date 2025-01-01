# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class RepositorySecurityConfiguration < Default
      def subject_attributes
        super.merge(
          "subject.organization.id" => participant.organization_id,
          "subject.repository.id" => participant.repository_id,
          "subject.security_configuration.id" => participant.security_configuration_id,
        )
      end
    end
  end
end
