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
    # Inherit the hash algorithm from the parent if one exists and otherwise use
    # the default.
    hash_algo = gist.parent ? gist.parent.hash_algo.name : nil

    copy_properties_from_parent if gist.fork?

    if !gist.valid?
      @errors = gist.errors
      return nil
    end

    set_repo_name

    before_oid = nil
    after_oid = nil

    # gist.contents gets cleared after gist.save!
    # so we need to store it to be able to restore in the event of any spokes errors
    contents = gist.contents
    # We need to get the initial commit data before the gist is saved
    initial_commit = nil
    if contents
      initial_commit = gist.build_initial_commit(contents)
    end

    # spokes requires the gist to be persisted first so it has an ID to use
    # in spokesdb.
    begin
      gist.save!
      Failbot.push "gh.gist.id": gist.id
    rescue Exception # rubocop:todo Lint/RescueException
      # `save!` could fail because of a failure during after_commit, which
      # means the record would actually exist in db.  Ensure that's not the
      # case.
      gist.destroy if gist.persisted?
      raise
    end

    # Create repository on file servers & insert to spokesdb for routing
    begin
      after_oid = create_repo(hash_algo: hash_algo, initial_commit: initial_commit)
    rescue SpokesAPI::Error => e
      # failed to create repository in spokesdb or on disk, roll back gist creation
      gist.destroy
      gist.contents = contents # restore contents to re-render on page

      # Handle invalid argument errors (eg. too many files) equivalent to GitRPC::RequestTooLarge
      if e.is_a?(SpokesAPI::InvalidArgument) && e.message.include?("may contain up to")
        gist.errors.add(:contents, "are too large and cannot be saved")
        @errors = gist.errors
        return nil
      end

      # Propagate all other errors
      raise e
    end

    # Reload routes now that the gist has been created
    gist.dgit_reload_routes!

    gist.assign_upload_container_id_to_user_assets

    if after_oid
      # Enqueue job post create to avoid race condition where Gist::Push job runs
      # prior to the record being fully saved.
      now = Time.current
      master_ref.enqueue_push_job(before_oid, after_oid, gist.user, now)
    end

    gist.clear_ref_cache
    gist.unmemoize_all

    # Instrument creation now that the repository is ready and files are available
    gist.instrument_creation

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
    gist.hash_algo = gist.parent.hash_algo
  end

  def set_repo_name
    gist.repo_name ||= Gist.generate_unique_repo_name
    Failbot.push "gh.gist.repo_name": gist.repo_name
  end

  def create_repo(hash_algo:, initial_commit:)
    repo_creator = GitHub::RepoCreator.new(gist,
                                           public: gist.public?,
                                           default_branch: gist_repo_branch,
                                           nwo: "gist/#{gist.repo_name}",
                                           hash_algo: hash_algo,
                                           initial_commit: initial_commit)

    if gist.parent
      ref = gist.parent.heads.find_or_build(gist.parent.default_branch)
      repo_creator.fork(gist.parent)
      ref.target_oid
    else
      repo_creator.init.head_oid.id
    end
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
