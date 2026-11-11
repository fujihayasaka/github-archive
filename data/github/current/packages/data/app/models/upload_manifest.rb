# typed: false
# frozen_string_literal: true

class UploadManifest < ApplicationRecord::Domain::Repositories
  include GitHub::Validations

  enum :state, {
    new: 0,
    uploaded: 1,
    committed: 2,
    failed: 3,
  }, prefix: true

  after_initialize :set_initial_state

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :uploader, class_name: "User"
  has_many :files, class_name: "UploadManifestFile", dependent: :delete_all

  validates :repository, presence: true
  validates :directory, bytesize: { maximum: 1024 }
  validates :uploader, presence: true
  validate  :uploader_access, on: :create
  validates_with UploadDirectoryValidator

  extend GitHub::Encoding
  force_utf8_encoding :directory

  def directory=(value)
    validator = UploadDirectoryValidator.new({})
    write_attribute :directory, validator.sanitize_directory_name(value)
  end

  # Determine if all of the manifest's files have been received and are ready
  # to commit to git.
  #
  # Returns true if all files have been uploaded.
  def complete?
    files.where(state: 0).empty?
  end

  # Store uploaded files for this manifest as a git commit. This method may
  # be called as many times as needed to move all files from S3 temporary
  # storage into the git repository.
  #
  # Returns nothing.
  def commit
    # Nothing to do when uploading, already committed, or failed.
    return unless state_uploaded?

    # User lost permissions between upload and commit.
    return unless repository.pushable_by?(uploader)

    # Combine blobs into a single commit.
    metadata = {
      message: message.present? ? message : "Add files via upload",
      author: uploader,
      authored_date: uploader.time_zone.now.iso8601,
    }

    ref = branch_ref
    commit = ref.append_commit(metadata, uploader, sign: true, target_oid: !ref.exist? ? base_ref&.target_oid : nil) do |files|
      self.files.each do |file|
        files.add(file.full_name, file.contents)
      end
    end

    # Track the commit we created for the user.
    update(commit_oid: commit.oid, state: :committed)

    cleanup
  end

  def cleanup
    # Create dangling temporary commits to be pruned later.
    if temp_ref && temp_ref.deleteable?(deleter: uploader)
      temp_ref.delete(uploader)
    end

    # Remove file uploads from temporary storage.
    files.each do |file|
      file.cleanup!
    end
  end

  # Queue a background job to commit the files in the manifest to git. Do
  # nothing if the manifest is already committed or not fully uploaded yet.
  #
  # branch        - The desired branch name String. This may be changed if it
  #                 already exists.
  # message       - The commit message String.
  # create_branch - Boolean indicating if the branch should be created or not
  #
  # Returns the JobStatus tracking the commit's progress.
  def schedule_commit(branch, message, create_branch)
    return unless state_uploaded?

    if create_branch
      branch = Git::Ref.normalize(branch) || repository.heads.temp_name(topic: "upload", prefix: uploader.login)
      branch = repository.heads.temp_name(topic: branch) if repository.heads.exist?(branch)
    end

    update(branch: branch, message: message)

    CommitUploadManifestJob.perform_later(id, nil, { status_ff: true })
  end

  def lfs_tracked_files(base_branch)
    # base_branch is nil for bare repo
    return [] unless base_branch && repository.has_lfs_files?

    commit_oid = repository.ref_to_sha(base_branch)
    file_paths = files.map { |file| file.full_name }
    filter_attribute_key = "filter"
    file_filter_attributes = repository.rpc.read_attributes(commit_oid, file_paths, keys: [filter_attribute_key])
    file_filter_attributes.select { |_file_path, attribute| attribute[filter_attribute_key] == "lfs" }.keys
  end

  private

  def set_initial_state
    self.state ||= :new
  end

  # Store the file contents as a git blob, and commit to a temporary ref
  # to prevent pruning.
  #
  # file - The UploadManifestFile to save as a blob.
  #
  # Returns nothing.
  def commit_blob(file)
    oid = file.to_blob

    metadata = {
      message: "Prevent blob pruning with a temporary commit",
      author: uploader,
      authored_date: uploader.time_zone.now.iso8601,
    }

    temp_ref.append_commit(metadata, uploader) do |files|
      files.add(file.full_name, { "oid" => oid })
    end
  end

  # Returns the ref on which the the final commit will be performed. This will
  # be "master" when directly editing the repository or ":login-upload-1" for
  # pull requests.
  #
  # Returns a Ref.
  def branch_ref
    name = branch.present? ? branch : repository.default_branch
    repository.heads.read(name)
  end

  def base_ref
    base_branch_name = base_branch.present? ? base_branch : repository.default_branch
    repository.heads.read(base_branch_name)
  end

  # Returns the hidden ref that points to blobs while they're being moved into
  # the repository. This prevents pruning from removing the blobs until we can
  # form the final commit. This ref can be deleted once the final commit is
  # complete.
  #
  # Returns a Ref.
  def temp_ref
    return unless repository

    name = "refs/__gh__/temp/upload-manifest/#{id}-#{created_at.to_i}"
    repository.refs.read(name)
  end

  def uploader_access
    if !repository.pushable_by?(uploader)
      errors.add :uploader, "does not have push access to this repository"
    end
  end

  def is_gitattributes_file?(file)
    Rugged.dotgit_attributes?(file.name)
  end
end
