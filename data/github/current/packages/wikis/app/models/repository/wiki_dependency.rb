# typed: false
# frozen_string_literal: true

module Repository::WikiDependency
  extend ActiveSupport::Concern

  SHOW_WIKI_TTL = 15.minutes

  def unsullied_wiki(force = false)
    @unsullied_wiki = nil if force
    @unsullied_wiki ||= begin
      u = GitHub::Unsullied::Wiki.new(self)
      u.on_update(&method(:bump_wiki_caches))
      u
    end
  end

  def wiki_exists_on_disk?
    RepositoryWiki.find_by(repository: self) && unsullied_wiki.exist?
  end

  def bump_wiki_caches(new_head_oid = nil)
    if repository_wiki = RepositoryWiki.find_by(repository: self)
      repository_wiki.increment_cache_version!
      unsullied_wiki.rpc.clear_repository_reference_key!

      repository_wiki.update_column(:pushed_at, Time.now)
    end
  end

  # Determines if the given user is allowed to edit the Wiki from the web UI.
  # Wiki repos follow the repository permissions for git pulls/pushes.
  #
  # user - A valid User instance.
  # user_can_pull - a boolean that indicates if we already know the user can pull from the repo.
  # user_can_pull - a boolean that indicates if we already know the user can push to the repo.
  #
  # Returns true if the user has access, or false.
  def wiki_writable_by?(user, user_can_pull: nil, user_can_push: nil)
    if world_writable_wiki
      return true if public? && user.is_a?(User)

      if user_can_pull.nil?
        user_can_pull = pullable_by?(user)
      end

      user_can_pull
    else
      if user_can_push.nil?
        user_can_push = pushable_by?(user)
      end

      user_can_push
    end
  end

  def wiki_world_writable?
    public? && world_writable_wiki
  end

  def wiki_access_to_pushers=(value)
    only_for_pushers = value && value != "0"
    self.world_writable_wiki = !only_for_pushers
  end

  def wiki_access_to_pushers
    !world_writable_wiki
  end

  alias wiki_access_to_pushers? wiki_access_to_pushers

  # Public: setup a wiki.
  def initialize_wiki(user, fork_parent_wiki: false)
    return if !user.can_edit_wikis?

    repo_wiki = RepositoryWiki.find_by(repository: self) || RepositoryWiki.create!(repository: self)

    return if unsullied_wiki.exist?

    begin
      unsullied_wiki.setup_git_repository(fork_parent_wiki: fork_parent_wiki)
    rescue ActiveRecord::ActiveRecordError, GitRPC::Error, GitHub::DGit::Error => e
      repo_wiki.destroy
      raise e
    end
  ensure
    # wiki_replicas was changed via an independent copy of this object, as
    # we only passed our id.  So reload here to pick up the change.
    if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      Repositories.domain.reload(self)
    else
      reload
    end
  end

  def wiki_path
    return "" if !owner

    name_with_display_owner.chomp(".wiki") + ".wiki.git"
  end

  def wiki_is_searchable?
    repo_is_searchable? && has_wiki? && wiki_exists_on_disk?
  end

  # When a repository has a wiki - or rather the wiki is not disabled in the settings - and the plan supports
  # it, show the link in the navigation. If there is no wiki and the user can't create one, don't show the link.
  def show_wiki?(current_user, user_can_write_wiki: nil)
    return false unless has_wiki? && plan_supports?(:wikis)
    return true if world_writable_wiki?

    if user_can_write_wiki.nil?
      user_can_write_wiki = wiki_writable_by?(current_user)
    end

    user_can_write_wiki || wiki_has_pages?
  end

  def wiki_has_pages?
    GitHub.cache.fetch("show_wiki:#{id}", ttl: SHOW_WIKI_TTL) do
      wiki = unsullied_wiki
      wiki.exist? && wiki.pages.count > 0 # rubocop:disable Lint/CountingZero since this is not an ActiveRecord relation
    end
  end
end
