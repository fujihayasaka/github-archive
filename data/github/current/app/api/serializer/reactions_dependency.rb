# typed: true
# frozen_string_literal: true

module Api::Serializer::ReactionsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::UserDependency }

  ReactionsRollupFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Reactable {
      reactionGroups {
        content
        users {
          totalCount
        }
      }
    }
  GRAPHQL

  ReactionFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Reaction {
      id
      databaseId
      createdAt
      content
      user {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
    }
  GRAPHQL

  def reactions_rollup(item, url)
    rollup = {
      url: url,
      total_count: 0,
    }
    Emotion.all.each do |emotion|
      count = item.reactions_count[emotion.content] || 0
      rollup[emotion.label] = count
      rollup[:total_count] += count
    end

    rollup
  end

  def reaction_hash(reaction, options = {})
    return nil if !reaction
    options = Api::SerializerOptions.from(options)

    {
      id: reaction.id,
      node_id: global_id_for(reaction, options),
      user: simple_user_hash(reaction.user, content_options(options)),
      content: reaction.emotion.label,
      created_at: time(reaction.created_at),
    }
  end

  def graphql_reaction_hash(reaction, options = {})
    options = Api::SerializerOptions.from(options)
    reaction = ReactionFragment.new(reaction)
    emotion = Emotion.find_by_platform_enum(reaction.content)

    {
      id: reaction.database_id,
      node_id: reaction.id,
      user: graphql_simple_user_hash(reaction.user, content_options(options)),
      content: emotion.label,
      created_at: time(reaction.created_at),
    }
  end

  def graphql_reactions_rollup(comment, url)
    comment = ReactionsRollupFragment.new(comment)
    rollup = {
      url: url,
      total_count: 0,
    }

    comment.reaction_groups.each do |reaction_group|
      api_label = Emotion.find_by_platform_enum(reaction_group.content).label.to_sym
      rollup[api_label] = reaction_group.users.total_count
      rollup[:total_count] += reaction_group.users.total_count
    end

    rollup
  end
end
