# typed: false
# frozen_string_literal: true

class Push < ApplicationRecord::Domain::RepositoriesPushes
  extend T::Sig
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  attribute :ref, StringFromBinary.new

  scope :branch_creation_or_deletion, -> { where(push_type: :branch_deletion).or(where(push_type: :branch_creation)) }
  scope :direct_push, -> { where.not(push_type: [:branch_deletion, :branch_creation, :pr_merge, :merge_queue_merge]) }

  validates :pushed_at, presence: true

  include Pushes::CommitsHelper
  include Pushes::ChangedFilesHelper
  include Repositories::IPush

  belongs_to  :repository
  belongs_to  :pusher, class_name: "User"

  before_create :set_push_type, if: -> { self.push_type.nil? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  delete_in_background_with :repository,
    sharding_key: :repository_id,
    sharding_value_key: :id

  # rubocop:enable GitHub/AvoidActiveRecordCallbacks

  attr_writer :commits
  attr_accessor :push_options, :skip_after_commit_callbacks, :spokes_api_fail_fast_enabled

  enum :push_type, {
    push: 0,
    force_push: 1,
    branch_deletion: 2,
    branch_creation: 3,
    pr_merge: 4,
    merge_queue_merge: 5,
  }, suffix: true

  def set_push_type(merge_method: nil, merge_action: nil)
    if merge_action == :merge_queue_merge || merge_action == :api_merge_queue_merge
      self.push_type = :merge_queue_merge
    elsif merge_method.present?
      self.push_type = :pr_merge
    elsif before == GitHub::NULL_OID
      self.push_type = :branch_creation
    elsif after == GitHub::NULL_OID
      self.push_type = :branch_deletion
    elsif non_fast_forward?
      self.push_type = :force_push
    else
      self.push_type = :push
    end
  end

  # Queries the db to see if we've recorded a force_push push_type for this push
  # If we have, this push is a non-fast forward push. Otherwise, fallback to the
  # CommitsHelper#non_fast_forward? module method.
  sig { override.returns T::Boolean }
  def non_fast_forward?
    self.force_push_push_type? || super
  end

  # Getting the url for a push
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                push.permalink(include_host: false) => `/github/github/compare/sd0979...9sd8fh`
  #
  def permalink(include_host: true)
    "#{repository.permalink(include_host: include_host)}/compare/#{before[0, 10]}...#{after[0, 10]}"
  end
  alias_method :url, :permalink

  def notifications_author
    pusher
  end

  def event_payload
    {
      event_prefix => self,
      :repo   => repository,
      :pusher => pusher,
      :ref    => ref,
      :before => before,
      :after  => after,
    }
  end

  def on_default_branch?
    return unless ref_is_branch?
    branch_name == repository.default_branch
  end

  def dependency_manifest_changed?
    return false unless repository.dependency_graph_enabled?
    return false unless changed_files
    return @dependency_manifest_changed if defined?(@dependency_manifest_changed)
    GitHub.dogstats.time("push.dependency_manifest_changed_check") do
      @dependency_manifest_changed = changed_files.any? do |file|
        DependencyManifestFile.recognized_path?(path: file.path)
      end
    end
  end

  def license_changed?
    RepositoryLicense.push_changed_license?(self)
  end

  def enqueue_dependency_manifest_changed_event
    return unless on_default_branch?
    return unless initial_commit? || dependency_manifest_changed?

    RepositoryDependencyManifestChangedJob.perform_later(id, repository_id)
  end

  def instrument_dependency_graph_snapshot_request
    if dependency_manifest_changed? && !GitHub.enterprise?
      manifest_files = changed_files(decompose_renames: true)&.reduce([]) do |manifest_files, file|
        next manifest_files unless DependencyManifestFile.recognized_path?(path: file.path)
        next manifest_files if file.deletion?

        manifest_files << {
          filename: File.basename(file.path),
          path: File.dirname(file.path).sub(/\A\.\z/, ""),
          blob_oid: file.oid
        }
      end

      return unless manifest_files.present?

      GlobalInstrumenter.instrument("dependency_graph.request_snapshot", {
        push_id: id,
        before_sha: before,
        sha: after,
        ref: ref,
        pushed_at: created_at,
        owner_name: repository.owner_display_login,
        repository: repository,
        manifest_files: manifest_files,
      })
    end
  end

  def enqueue_set_license
    RepositorySetLicenseJob.perform_later(repository)
  end

  def create_check_suites
    return if CheckSuites::Public.skip_checks_for_push?(push: self)
    CreateCheckSuitesJob.enqueue(push_id: id, repository_id: repository_id)
  end

  def branch_protection_rule
    return unless ref_is_branch?

    ProtectedBranch.for_repository_with_branch_name(repository, branch_name)
  end

  # Public: Adds an index hint
  #
  # index - the index to suggest
  #
  # Returns nothing.
  sig { params(index: String).returns(T.untyped) }
  def self.use_index(index)
    from("#{self.table_name} USE INDEX(#{index})")
  end
end
