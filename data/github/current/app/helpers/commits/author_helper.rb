# typed: true
# frozen_string_literal: true

module Commits::AuthorHelper
  include CommitHelper
  include UrlHelper
  include TextHelper
  include AvatarHelper

  def initialize_commit_authors(commit, current_user, include_pusher: false)
    committer_attribution = !commit.async_authored_by_committer?.sync && !commit.committed_via_web?
    authors = commit.async_unique_visible_author_actors(current_user).sync
    authors_out = []

    authors.each do |author|
      author_user = author.visible_actor(current_user)

      author_actor = {}.tap do |opts|
        opts[:login]             = author_user&.display_login
        opts[:displayName]       = author.display_name
        opts[:avatarUrl]         = author_user&.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
        opts[:path]              = user_path(author_user) unless author_user.nil?
        opts[:isGitHub]          = false
      end
      authors_out << author_actor
    end

    committer = commit.committer_actor
    if committer != nil
      commiter_user = committer.visible_actor(current_user)

      committer_out = {}.tap do |opts|
        opts[:login]             = commiter_user&.display_login
        opts[:displayName]       = committer.display_name
        opts[:avatarUrl]         = commiter_user&.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
        opts[:path]              = user_path(commiter_user) unless commiter_user.nil?
        opts[:isGitHub]          = commit.committed_via_web?
      end
    end

    pusher_out = nil
    pushed_at = nil
    if include_pusher && commit.repository&.feature_flag_enabled_or_raise?(:show_pusher_on_commit_detail) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      push = Repositories.domain.pushes.by_commit(
        repository_id: commit.repository.id,
        repository_network_id:
        commit.repository.network_id, oid: commit.sha)
      if push&.pusher.present?
        push = T.must(push)
        pusher = T.must(push.pusher)
        avatar_url = User.find_by(id: pusher.id)&.primary_avatar_url
        pusher_out = {}.tap do |opts|
          opts[:login]             = pusher.display_login
          opts[:displayName]       = pusher.display_login
          opts[:avatarUrl]         = avatar_url || User::AvatarList.default_image_url("gravatar-user-420")
          opts[:path]              = user_path(pusher)
          opts[:isGitHub]          = false
        end
        pushed_at = push.pushed_at&.iso8601
      end
    end

    {
      authors: authors_out,
      committerAttribution: committer_attribution,
      committer: committer_out,
      pusher: pusher_out,
      pushedDate: pushed_at,
    }
  end

  def prefill_commit_author_associations(commits, current_user)
    return unless commits.present?

    promises = prefill_commit_author_promises(commits, current_user)

    Promise.all(promises).sync
  end

  def prefill_commit_author_promises(commits, current_user)
    promises = commits.flat_map do |commit|
      [
        commit.author_actors.map { |git_actor| [git_actor.async_visible_actor(current_user)] },
        commit.committer_actor.async_visible_actor(current_user),
        commit.async_authored_by_committer?,
        commit.async_unique_visible_author_actors(current_user).then { |authors| authors.map { |author| author.async_visible_user(current_user) } },
      ].flatten
    end
  end
end
