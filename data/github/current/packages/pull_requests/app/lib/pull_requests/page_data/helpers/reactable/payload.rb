# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Helpers::Reactable
  class Payload
    class ReactionContent < T::Enum
      enums do
        Confused = new("CONFUSED")
        Eyes = new("EYES")
        Heart = new("HEART")
        Hooray = new("HOORAY")
        Laugh = new("LAUGH")
        Rocket = new("ROCKET")
        ThumbsDown = new("THUMBS_DOWN")
        ThumbsUp = new("THUMBS_UP")
      end
    end

    class Reaction < T::Struct
      const :content, ReactionContent
      const :viewerHasReacted, T::Boolean
    end

    class ReactorTypeName < T::Enum
      enums do
        User = new("User")
        Organization = new("Organization")
        Bot = new("Bot")
        Mannequin = new("Mannequin")
      end
    end

    class Reactor < T::Struct
      const :login, String
      const :typeName, ReactorTypeName
    end

    class ReactionGroup < T::Struct
      const :reaction, Reaction
      const :reactors, T::Array[Reactor]
      const :totalCount, Integer
    end

    sig { params(reaction_groups: T::Array[PullRequests::PageData::Helpers::Reactable::Loader::ReactionGroup]).returns(T::Array[ReactionGroup]) }
    def self.build_reaction_groups(reaction_groups)
      reaction_groups.map do |reaction_group|
        reactors = reaction_group.reactors.map do |reactor|
          Reactor.new(
            login: reactor.login, # rubocop:disable GitHub/DoNotAllowLogin
            typeName: reactor.type_name
          )
        end

        ReactionGroup.new(
          reaction: Reaction.new(
            content: reaction_group.reaction.content,
            viewerHasReacted: reaction_group.reaction.viewer_has_reacted
          ),
          reactors: reactors,
          totalCount: reaction_group.total_count
        )
      end
    end
  end
end
