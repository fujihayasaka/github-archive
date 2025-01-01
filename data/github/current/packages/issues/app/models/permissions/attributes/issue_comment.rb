# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class IssueComment < Default
      def subject_attributes
        super.merge(
          "subject.author.id"             => participant.user_id,
          "subject.business.id"           => participant.repository.owner&.async_business&.sync&.id,
          "subject.owner.id"              => participant.repository.owner_id,
          "subject.owning_organization.id" => participant.repository.owning_organization_id,
          "subject.repository.archived"   => participant.repository.archived?,
          "subject.repository.owner.id"   => participant.repository.owner_id,
          "subject.repository.owner.type" => participant.repository.owner.class.name,
          "subject.repository.id"         => participant.repository.id,
          "subject.repository.internal"   => participant.repository.internal?,
          "subject.repository.public"     => participant.repository.public?,
        )
      end
    end
  end
end
