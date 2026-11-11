# typed: true
# frozen_string_literal: true

module Permissions
  module Attributes
    class DiscussionComment < Default
      sig { returns(T.untyped) }
      def subject_attributes
        super.merge(
          "subject.wiped"                      => participant.wiped?,
          "subject.answer"                     => participant.answer?,
          "subject.discussion.allow_reactions" => participant.discussion&.allow_reactions?,
          "subject.discussion.locked"          => participant.discussion&.locked?,
          "subject.author.id"                  => participant.user_id,
          "subject.discussion.author.id"       => participant.discussion&.user_id,
          "subject.repository.id"              => participant.repository_id,
          "subject.repository.writable"        => participant.repository&.writable?,
          "subject.repository.public"          => participant.repository&.public?,
          "subject.repository.internal"        => participant.repository&.internal?,
          "subject.repository.owner.id"        => participant.repository&.owner_id,
          "subject.owner.id"                   => participant.repository&.owner_id,
          "subject.repository.owner.type"      => participant.repository&.owner&.class.name,
          "subject.business.id"                => participant.repository&.owner&.async_business.sync&.id,
          "subject.organization.id"            => participant.repository&.owner&.organization? ? participant.repository.owner.id : nil,
        )
      end
    end
  end
end
