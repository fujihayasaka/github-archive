# typed: true
# frozen_string_literal: true

# Factory class used to facilitate gist creation.
#
# Accepts the following attributes:
# user: User instance, tied to the current_user
# public: Boolean (optional)
# description: String description of the gist
# contents: Array of content object in the form of {name: fileanme, value: string content}
# creator_ip: string | nil
# parent: Gist instance (optional)
#

class Gist::Creator
  attr_reader :gist, :errors

  def self.create!(args = {})
    creator = new(args)
    if gist = creator.create
      gist
    else
      raise ArgumentError, "Could not create Gist: #{creator.errors.full_messages.to_sentence}"
    end
  end

  def initialize(attributes = {})
    # create overwrites any `delete_flag` value
    raise ArgumentError, "delete_flag is not allowed" if attributes.key?(:delete_flag)

    attributes.merge!(delete_flag: true)
    @gist = Gist.new(with_visibility(attributes))
  end

  def create
    copy_properties_from_parent if gist.fork?

    if !gist.valid?
      @errors = gist.errors
      return nil
    end

    set_repo_name
    create_repo

    # Capture before_oid before we commit contents
    before_oid = master_ref.target_oid
    begin
      # New OID is only present if there's any contents to commit
      after_oid = commit_contents || before_oid
    rescue GitRPC::RequestTooLarge
      @errors = gist.errors
      return nil
    end

    # This block is exclusively for saving the record. If any exception happens,
    # we back out of it and remove the on-disk contents because we treat it as
    # failing to insert the gist in the table.
    begin
      gist.save!
      Failbot.push "gh.gist.id": gist.id
    rescue Exception # rubocop:todo Lint/RescueException
      # if we're unable to insert the Gist record for whatever reason, we don't
      # want to leave a dangling repository on disk.
      gist.rpc.remove
      # `save!` could fail because of a failure during after_commit, which
      # means the record would actually exist in db.  Ensure that's not the
      # case.
      gist.destroy if gist.persisted?
      raise
    end

    begin
      save_dgit_routes
    rescue Exception # rubocop:todo Lint/RescueException
      # If we're having a database issue saving routes, calling destroy may hit
      # the same situation. On delete we will try to cleanup any replica and
      # checksum rows. To avoid leaving danging gists around, we will remove
      # the content first even though these steps are not strictly reverse
      # order.
      gist.rpc.remove
      gist.destroy
      raise
    end

    # Now that our gist has an id and routes have been saved to the database we
    # can clear our special delegate.
    gist.dgit_delegate = nil

    # Enqueue job post create to avoid race condition where Gist::Push job runs
    # prior to the record being fully saved.
    now = Time.current
    master_ref.enqueue_push_job(before_oid, after_oid, gist.user, now)

    gist.clear_ref_cache
    gist.unmemoize_all

    gist.async_backup(opts: { pushed_at: now })

    @errors = nil
    gist.update(delete_flag: false)
    gist
  end

  private

  def master_ref
    gist.heads.find_or_build(gist_repo_branch)
  end

  def gist_repo_branch
    gist.fork? ? gist.parent.default_branch : gist&.user&.default_new_repo_branch || "main"
  end

  def copy_properties_from_parent
    gist.public = gist.parent.public
    gist.description = gist.parent.description
    gist.pushed_at = gist.parent.pushed_at
  end

  def set_repo_name
    gist.repo_name ||= Gist.generate_unique_repo_name
    Failbot.push "gh.gist.repo_name": gist.repo_name
  end

  def create_repo
    fileservers = GitHub::Spokes.client.pick_fileservers(actor: gist.user)

    # Gist delegate's require special handling because we try to create them on
    # disk prior to saving them in the database.
    gist.dgit_delegate = GitHub::DGit::Delegate::GistCreation.new(gist.repo_name, gist.original_shard_path, fileservers)

    repo_creator = GitHub::RepoCreator.new(gist,
                                           public: gist.public?,
                                           default_branch: gist_repo_branch,
                                           nwo: "gist/#{gist.repo_name}")

    if gist.parent
      repo_creator.fork(gist.parent)
    else
      repo_creator.init
    end

    GitHub::DGit::Maintenance.init_gist_checksums(gist)
  end

  def save_dgit_routes
    gist_fileservers = gist.dgit_delegate.get_write_routes.map(&:fileserver)

    GitHub::DGit::Maintenance.insert_placeholder_gist_replicas_and_checksums(
      gist.id, gist_fileservers)

    # Provide the set of `gist_fileservers` already computed here so that
    # `recompute_gist_checksums` does not re-issue routing queries.
    GitHub::DGit::Maintenance.recompute_gist_checksums(
      gist,
      gist.dgit_read_routes.first.original_host,
      fileservers: gist_fileservers)
  end

  def commit_contents
    if gist.contents
      gist.commit_contents!(gist.contents)
    end
  end

  def with_visibility(attributes)
    visibility = [attributes[:public], attributes[:parent]&.public, false].compact.first
    attributes.merge(public: visibility)
  end
end
