# typed: true
# frozen_string_literal: true

class Mirror < ApplicationRecord::Domain::Repositories

  class MirrorError < StandardError; end

  belongs_to :repository
  validates_presence_of :url

  before_validation :strip_whitespace

  validate do |mirror|
    next if mirror.url.blank?
    uri = URI(mirror.url)

    if !%w[git http https].include?(uri.scheme)
      mirror.errors.add :url, "must be a git://, http:// or https:// url"
    end

    if uri.host == GitHub.host_name
      mirror.errors.add :url, "cannot be a GitHub repository"
    end
  end

  # Current mirror lag time. That is, the maximum amount of time any mirror
  # will be out of sync with its upstream repository. This number increases as
  # more mirrors are added since we mirror a fixed number of repositories every
  # 10 minutes.
  #
  # Returns the number of seconds since the most stale mirror was last
  # synchronized, or nil when no mirrors exist.
  def self.lag
    if stalest = order("updated_at ASC").first
      Time.now - stalest.updated_at
    end
  end

  # Schedules least recently mirrored repositories for mirroring. Called from
  # timerd every 10 minutes. Each mirror is run in a separate mirror job.
  #
  # count - Maximum number of mirrors to schedule.
  #
  # Returns nothing.
  def self.schedule_pending(count)
    order("updated_at ASC").limit(count).to_a.each { |mirror| mirror.perform }
  end

  # Enqueue a mirror job.
  def perform
    if repository
      with_write { update_attribute :updated_at, Time.now }
      RepositoryMirrorJob.perform_later(repository_id)
    end
    true
  end

  # Perform the actual mirror operation.  If remote refs were modified,
  # execute the repository's post-mirror job.  The post-mirror job
  # run the repository push job on its own queue.
  def perform!
    # XXX bug in eventmachine causes problems when timeout is > 2142
    # TODO: GitRPC per call timeout 2000.seconds
    mirror_prefix = "refs/__gh__/temp/mirror-#{$$}-#{Time.now.to_i}/"
    mirror_env = {
      "GIT_COMMITTER_DATE"  => Time.current.to_formatted_s(:git),
      "GIT_COMMITTER_NAME"  => "mirrors",
      "GIT_COMMITTER_EMAIL" => "mirrors@users.noreply.#{GitHub.host_name}",
    }
    hiderefs_env = {
      "GIT_CONFIG_PARAMETERS" => "'transfer.hiderefs=refs/__gh__'",
    }
    if GitHub.mirror_pusher
      mirror_env["GIT_PUSHER"] = GitHub.mirror_pusher
    end

    # Copy all of the remote's refs to a temporary namespace. We only run this on the read replica initially to get the changes into our machines.
    reader = T.must(repository).dgit_read_routes.first
    others = T.must(repository).dgit_write_routes.select { |route| route.original_host != reader.original_host }
    rrpc = reader.build_maint_rpc

    source_ref_specs = ["refs/branch-heads/*:refs/branch-heads/*", "refs/heads/*:refs/heads/*", "refs/tags/*:refs/tags/*", "HEAD:HEAD"]

    mirror_refs = rrpc.fetch_for_mirror(url, source_ref_specs, mirror_prefix, mirror_env.merge(hiderefs_env))

    # Fetch the just-fetched refs to all other replicas. This could be
    # parallelized, but it would make the code a lot messier (BERT muxes and all
    # that), and transfers within DGit are pretty fast.
    others.each do |route|
      wrpc = route.build_maint_rpc
      wrpc.fetch_for_mirror(reader.remote_url, mirror_prefix, mirror_prefix, mirror_env)
    end

    # Make a list of changed refs to pass to update-refs and the
    # post-mirror job.
    old_refs = Hash[
                      T.must(repository).all_refs.select { |ref| !ref.qualified_name.start_with?("refs/__gh__/") }
                                         .select { |ref| !ref.qualified_name.start_with?("refs/pull/") }
                                         .map    { |ref| [ref.qualified_name, ref.sha] }
               ]
    new_refs = Hash[
                              mirror_refs.map    { |name, oid| [name[mirror_prefix.length..-1], oid] }
                                         .select { |name, _oid| !name.start_with?("refs/pull/") }
               ]
    remote_head_oid = new_refs["HEAD"]
    new_refs.delete_if { |name, _oid| !name.start_with?("refs/") }

    # limit the number of refs that can be deleted to 5,000 to avoid timeouts
    # the next run will continue to delete any leftover refs
    deleted_refs = (old_refs.keys - new_refs.keys).take(5000)
    added_refs = new_refs.keys - old_refs.keys
    changed_refs = old_refs.select { |ref, oid| new_refs.key?(ref) && oid != new_refs[ref] }.keys

    # Make the local HEAD match the remote HEAD.
    # Prefer main, master, or trunk if it has the same SHA1.  Otherwise set whatever
    # matching branch is alphabetically first.  If there are no matching
    # branches, default to refs/heads/main.
    preferred_heads = %w{refs/heads/main refs/heads/master refs/heads/trunk}.freeze
    if remote_head_oid
      candidates = new_refs.select { |ref, oid| ref =~ /^refs\/heads\// && oid == remote_head_oid }

      head = preferred_heads.find { |name| candidates.has_key?(name) }
      head ||= if candidates.any?
        candidates.sort_by { |ref, _oid| ref }.first&.first
      end
    end
    head ||= preferred_heads.first
    begin
      refpath = repository&.get_default_branch
    rescue SpokesAPI::ResourceExhausted
      # request was rate limited
      raise
    rescue GitRPC::Error, SpokesAPI::Error
    end
    if refpath != head
      begin
        repository&.update_default_branch_spokes(head)
      rescue GitRPC::RefUpdateError => e
        raise MirrorError, "setting symbolic-ref failed, err=#{e.message}"
      end
    end

    # Commit the changes using 3PC
    committed_at = nil
    if added_refs.any? || deleted_refs.any? || changed_refs.any?
      GitHub.logger.info(
        "Updating mirror refs",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.repo.id" => repository_id,
        "gh.repo.mirror.deleted_count" => deleted_refs.size,
        "gh.repo.mirror.added_count" => added_refs.size,
        "gh.repo.mirror.changed_count" => changed_refs.size,
        "gh.repo.mirror.deleted" => deleted_refs,
        "gh.repo.mirror.added" => added_refs,
        "gh.repo.mirror.changed" => changed_refs
      )
      changes = deleted_refs.map  { |ref| [ref, old_refs[ref], GitHub::NULL_OID] }
      changes += added_refs.map   { |ref| [ref, GitHub::NULL_OID, new_refs[ref]] }
      changes += changed_refs.map { |ref| [ref, old_refs[ref], new_refs[ref]] }
      tpc = ::GitHub::DGit.update_refs_coordinator(repository)
      sockstat = {
                   committer_name: mirror_env["GIT_COMMITTER_NAME"],
                   committer_email: mirror_env["GIT_COMMITTER_EMAIL"],
                 }
      txn_status = tpc.commit(changes, sockstat, "mirror")
      committed_at = txn_status[:committed_at]
      raise MirrorError, "error committing mirrored 3pc changes to repo #{repository_id}" if txn_status[:err]
      raise MirrorError, "Some mirrored ref updates failed for repo #{repository_id}" if txn_status[:refs_status].any?
    end

    deleted_temp_refs = true  # don't attempt temp-ref deletion twice
    delete_temp_refs(mirror_prefix, mirror_env)

    # Enqueue post-mirror job if there are any updates
    if added_refs.any? || deleted_refs.any? || changed_refs.any?
      # apache mirror include refs twice
      isrefsremotes = lambda { |ref| ref.include?("refs/remotes") }
      job_refs = deleted_refs.reject(&isrefsremotes).map { |ref| [ref, old_refs[ref], GitHub::NULL_OID] }
      job_refs += added_refs.reject(&isrefsremotes).map { |ref| [ref, GitHub::NULL_OID, new_refs[ref]] }
      job_refs += changed_refs.reject(&isrefsremotes).map { |ref| [ref, old_refs[ref], new_refs[ref]] }

      ref_updates = job_refs.map do |ref_update|
        ::Git::Ref::Update.new(repository: repository, refname: ref_update[0], before_oid: ref_update[1], after_oid: ref_update[2])
      end
      RepositoryPushJobTrigger.new(repository, mirror_env["GIT_PUSHER"], ref_updates, committed_at).enqueue
    end

    [old_refs, new_refs]

  ensure
    delete_temp_refs(mirror_prefix, mirror_env) unless deleted_temp_refs
  end

  private

  def delete_temp_refs(mirror_prefix, mirror_env)
    # Delete temp refs whether or not the mirror succeeds.
    #
    # If we failed when trying to `git fetch` temp refs from one DGit
    # replica to another, they may actually have differing sets of refs.
    # repository.all_refs will pull from the current reader, which
    # will usually be the same as the reader that got the temp refs above,
    # but not always.
    #
    # Trying to delete temp refs on all replicas when they only exist on
    # one is actually just fine -- `update-ref` ignores deletes for
    # missing refs.
    #
    # In cases where the reader changed mid-function and the
    # replica-to-replica `git fetch` failed, we may leave stale temp refs
    # behind, and they'll have to get cleaned up by a future
    # `Mirror#perform!` call.
    T.must(repository).rpc.delete_mirror_temp_refs(mirror_prefix, (Time.now - 2.days).to_i, mirror_env)
  rescue GitRPC::CommandFailed => e
    $stderr.puts "Could not delete temp refs: #{e.message}"
  end

  def strip_whitespace
    self.url = T.must(self.url).strip unless self.url.blank?
  end
end
