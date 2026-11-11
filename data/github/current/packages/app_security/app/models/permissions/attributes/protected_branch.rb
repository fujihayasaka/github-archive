# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class ProtectedBranch < Default
      def subject_attributes
        super.merge(
          "subject.source_type"                                       => :repository,
          "protected_branch.push_restrictions.authorized_users_only"  => participant.has_authorized_actors?,
          "subject.repository.id"                                     => participant.repository.id,
          "repository.public"                                         => participant.repository.public?,
          "repository.owner.id"                                       => participant.repository.owner_id,
          "repository.owner.type"                                     => participant.repository.owner.class.name,
          "subject.repository.owner.type"                             => participant.repository.owner.class.name,
          "subject.owner.id"                                          => participant.repository.owner_id,
          "subject.repository.owner.id"                               => participant.repository.owner_id,
          "subject.business.id"                                       => participant.repository.owner&.async_business&.sync&.id,
          "subject.organization.id"                                   => participant.repository.owner&.organization? ? participant.repository.owner.id : nil,
        )
      end
    end
  end
end
