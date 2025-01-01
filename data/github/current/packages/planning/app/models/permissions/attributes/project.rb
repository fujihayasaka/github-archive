# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Project < Default
      def subject_attributes
        case participant.owner_type
        when "Repository"
          repository = participant.owner
          owning_organization_id = repository&.owning_organization_id
        when "Organization"
          organization_id = participant.owner_id
          owning_organization_id = organization_id
        end
        super.merge(
          "subject.creator.id"             => participant.creator_id,
          "subject.public"                 => participant.public,
          "subject.owner.id"               => participant.owner_id,
          "subject.owner.type"             => participant.owner_type,
          "subject.repository.id"          => repository&.id,
          "subject.repository.public"      => repository&.public?,
          "subject.repository.internal"    => repository&.internal?,
          "subject.repository.owner.id"    => repository&.owner_id,
          "subject.repository.owner.type"  => repository&.owner.class.name,
          "subject.organization.id"        => organization_id,
          "subject.owning_organization.id" => owning_organization_id,
          "subject.business.id"            => repository&.owner&.async_business&.sync&.id,
        )
      end
    end
  end
end
