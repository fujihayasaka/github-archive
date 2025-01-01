# typed: true
# frozen_string_literal: true

class HydroWikisOnPushJob < Repositories::PushHydroMessageJob
  use_primaries ApplicationRecord::Repositories #repository_wikis

  applies_to_wikis!

  queue_as :hydro_wikis_on_push

  def stale?
    repository.owner.nil? || repository.nil? || repository.unsullied_wiki.nil? || !repository.unsullied_wiki.exist?
  end

  sig { void }
  def perform
    return unless wiki?

    repository.bump_wiki_caches

    repository_wiki = RepositoryWiki.find_by!(repository:)
    repository_wiki.pushed_count += 1
    repository_wiki.pushed_count_since_maintenance += 1
    repository_wiki.save!

    repository.async_backup_wiki(opts: { pushed_at: pushed_at })

    create_wiki_events

    # https://github.com/github/platform-health/issues/2770
    wiki_repository_payload = {
      pusher: pusher,
      repository: repository,
      owner: repository.owner,
      request_context: request_context,
      wiki_world_writable: repository.wiki_world_writable?,
      ref_updates: ref_updates.map { |ref_update| [ref_update.ref, ref_update.before, ref_update.after] },
      pushed_at: pushed_at,
      business_id: repository.owner&.business&.id
    }

    if SecretScanning::Features::Repo::WikiScanning.new(repository).enabled?
      wiki_repository_payload[:feature_flags] = repository.post_receive_instrumentation_feature_flags
    end

    GlobalInstrumenter.instrument("wiki.edit", wiki_repository_payload)
  end

  def create_wiki_events
    ref_updates.each do |ref_update|
      return if ref_update.deleted? || stale? || !ref_update.branch_or_tag? || ref_update.branch_name != "master" # Wikis always use "master"

      after_commit = commit(ref_update.after, repository.unsullied_wiki)
      return if after_commit.nil?

      # TODO: GitRPC per call timeout 5.minutes
      create_events(after_commit)
    end
  end

  def create_events(commit)
    actor_id = user_id(commit)

    return unless actor_id
    updates   = []

    added_pages, modified_pages = scan_diffs(commit)

    added_pages.each do |page|
      updates << wiki_update_for(page, :created)
    end

    modified_pages.each do |page|
      updates << wiki_update_for(page, :edited)
    end

    return unless updates.present?

    # TODO: Look into why we don't use the pusher as the actor???
    GitHub.instrument "wiki.push", actor_id: actor_id, repo_id: repository.id, updates: updates
  end

  def wiki_update_for(page, action)
    { action: action, page_name: page.name, sha: page.revision_oid.to_s }
  end

  def commit(after, wiki)
    begin
      wiki.commits.find(after)
    rescue GitRPC::InvalidObject
      nil
    end
  end

  def scan_diffs(commit)
    diffs = commit.diff
    added_pages    = []
    modified_pages = []
    diffs.each do |diff|
      next if diff.deleted?

      local = File.basename("#{diff.b_path || diff.a_path}")
      next if local.blank?
      name  = ::File.basename(local, ::File.extname(local))
      next if name.blank?

      page = repository.unsullied_wiki.pages.find(name, commit.oid)
      next if page.nil?

      if diff.added?
        added_pages << page
      else
        modified_pages << page
      end
    end

    [added_pages, modified_pages]
  end

  def user_id(commit)
    return unless commit.author_email.present?
    # EMUs can have the same commit emails as users, so we may need to look up the user by business and email
    user = if repository.is_enterprise_managed?
      User.find_by_email(commit.author_email, business: repository.business)
    else
      User.find_by_email(commit.author_email)
    end
    user&.id
  end
end
