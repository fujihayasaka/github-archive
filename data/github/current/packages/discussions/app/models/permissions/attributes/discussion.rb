# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class Discussion < Default
      sig { returns(T.untyped) }
      def subject_attributes
        super.merge(
          "subject.locked"                => participant.locked?,
          "subject.allow_reactions"       => participant.allow_reactions?,
          "subject.author.id"             => participant.user_id,
          "subject.closer.id"             => participant.closed? ? participant.closed_by&.id : nil,
          "subject.repository.id"         => participant.repository_id,
          "subject.repository.writable"   => participant.repository&.writable?,
          "subject.repository.public"     => participant.repository&.public?,
          "subject.repository.internal"   => participant.repository&.internal?,
          "subject.business.id"           => participant.repository&.owner&.async_business&.sync&.id,
          "subject.owner.id"              => participant.repository&.owner_id,
          "repository.owner.id"           => participant.repository&.owner_id,
          "subject.repository.owner.id"   => participant.repository&.owner_id,
          "subject.repository.owner.type" => participant.repository&.owner&.class&.name,
        )
      end
    end
  end
end
