# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Helpers::Reactable
  class Loader
    include GitHub::ResilienceMixin

    class Reaction < T::Struct
      const :content, PullRequests::PageData::Helpers::Reactable::Payload::ReactionContent
      const :viewer_has_reacted, T::Boolean
    end

    class Reactor < T::Struct
      const :login, String
      const :type_name, PullRequests::PageData::Helpers::Reactable::Payload::ReactorTypeName
    end

    class ReactionGroup < T::Struct
      const :reaction, Reaction
      const :reactors, T::Array[Reactor]
      const :total_count, Integer
    end

    sig { params(comment: T.any(PullRequestReviewComment, CommitComment), viewer: T.nilable(User)).returns(Promise[T::Array[PullRequests::PageData::Helpers::Reactable::Loader::ReactionGroup]]) }
    def self.async_reaction_groups(comment, viewer)
      reaction_users_by_emoji = Hash.new { |h, k| h[k] = [] }

      comment.reactions.map do |reaction|
        reaction_users_by_emoji[reaction.content] << reaction.user
      end

      comment.async_reaction_groups.then do |reaction_groups|
        reaction_groups.map do |reaction_group|
          reactive_users = reaction_users_by_emoji[reaction_group.emotion.content] || []
          reaction = PullRequests::PageData::Helpers::Reactable::Loader::Reaction.new(
            content: PullRequests::PageData::Helpers::Reactable::Payload::ReactionContent.deserialize(reaction_group.emotion.platform_enum),
            viewer_has_reacted: reactive_users.include?(viewer)
          )

          reactors = reactive_users.map do |reactive_user|
            PullRequests::PageData::Helpers::Reactable::Loader::Reactor.new(
              login: reactive_user.display_login,
              type_name: PullRequests::PageData::Helpers::Reactable::Payload::ReactorTypeName.deserialize(reactive_user.type)
            )
          end

          PullRequests::PageData::Helpers::Reactable::Loader::ReactionGroup.new(
            reaction: reaction,
            reactors: reactors,
            total_count: reaction_group.total_count
          )
        end
      end
    end
  end
end
