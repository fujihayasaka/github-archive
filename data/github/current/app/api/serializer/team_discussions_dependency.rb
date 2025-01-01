# typed: false
# frozen_string_literal: true

module Api::Serializer::TeamDiscussionsDependency
  TeamDiscussionFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on TeamDiscussion {
      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
      id
      body
      bodyHTML
      bodyVersion
      comments {
        totalCount
      }
      createdAt
      lastEditedAt
      isPinned
      isPrivate
      number
      team {
        databaseId
        description
        ldapDn
        name
        permission
        privacy
        slug

        organization {
          databaseId
        }
      }
      title
      updatedAt
      url
      ...Api::Serializer::ReactionsDependency::ReactionsRollupFragment
    }
  GRAPHQL

  TeamDiscussionCommentFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on TeamDiscussionComment {
      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
      id
      body
      bodyHTML
      bodyVersion
      createdAt
      lastEditedAt
      discussion {
        number
        team {
          databaseId
          organization {
            databaseId
          }
        }
      }
      number
      updatedAt
      url
      ...Api::Serializer::ReactionsDependency::ReactionsRollupFragment
    }
  GRAPHQL

  def graphql_team_discussion_hash(discussion, options = {})
    serializer_options = Api::SerializerOptions.from(options)
    discussion = TeamDiscussionFragment.new(discussion)

    result = {
      author: author_hash(discussion.author, serializer_options),
      body: discussion.body,
      body_html: discussion.body_html,
      body_version: discussion.body_version,
      comments_count: discussion.comments.total_count,
      comments_url: url("#{discussion_url_path(discussion)}/comments"),
      created_at:  time(discussion.created_at),
      last_edited_at: time(discussion.last_edited_at),
      html_url: discussion.url.to_s,
      node_id: discussion.id,
      number: discussion.number,
      pinned: discussion.is_pinned?,
      private: discussion.is_private?,
      team_url: url(team_url_path(discussion.team)),
      title: discussion.title,
      updated_at:  time(discussion.updated_at),
      url: url(discussion_url_path(discussion)),
    }

    result[:reactions] = graphql_reactions_rollup(discussion, url(discussion_reactions_url_path(discussion)))
    result
  end

  def graphql_team_discussion_comment_hash(comment, options = {})
    serializer_options = Api::SerializerOptions.from(options)
    comment = TeamDiscussionCommentFragment.new(comment)

    result = {
      author: author_hash(comment.author, serializer_options),
      body: comment.body,
      body_html: comment.body_html,
      body_version: comment.body_version,
      created_at:  time(comment.created_at),
      last_edited_at: time(comment.last_edited_at),
      discussion_url: url(discussion_url_path(comment.discussion)),
      html_url: comment.url.to_s,
      node_id: comment.id,
      number: comment.number,
      updated_at:  time(comment.updated_at),
      url: url(comment_url_path(comment)),
    }

    result[:reactions] = graphql_reactions_rollup(comment, url(comment_reactions_url_path(comment)))
    result
  end

  private def author_hash(graphql_user, serializer_options)
    if graphql_user
      graphql_simple_user_hash(graphql_user, serializer_options)
    else
      simple_user_hash(User.ghost, serializer_options)
    end
  end

  private def team_url_path(team)
    "/organizations/#{team.organization.database_id}/team/#{team.database_id}"
  end

  private def discussion_url_path(discussion)
    "#{team_url_path(discussion.team)}/discussions/#{discussion.number}"
  end

  private def discussion_reactions_url_path(discussion)
    "#{team_url_path(discussion.team)}/discussions/#{discussion.number}/reactions"
  end

  private def comment_url_path(comment)
    "#{discussion_url_path(comment.discussion)}/comments/#{comment.number}"
  end

  private def comment_reactions_url_path(comment)
    "#{discussion_url_path(comment.discussion)}/comments/#{comment.number}/reactions"
  end
end
