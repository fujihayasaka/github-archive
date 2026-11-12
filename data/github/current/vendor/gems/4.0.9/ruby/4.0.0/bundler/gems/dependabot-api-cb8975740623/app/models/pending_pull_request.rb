# frozen_string_literal: true

require "rbnacl"

class PendingPullRequest < ApplicationRecord
  T.unsafe(self).include Statesman::Adapters::ActiveRecordQueries[
    transition_class: PendingPullRequestTransition,
    transition_name: :pending_pull_request_transition,
    initial_state: :pending
  ]
  include CurrentStateHelpers

  class DependencyFilesNotFound < StandardError; end

  belongs_to :update_job
  belongs_to :dependency_group, optional: true
  has_many :pending_pull_request_transitions,
           autosave: false,
           dependent: :destroy
  has_one :update_config,
          through: :update_job,
          inverse_of: :pending_pull_requests

  has_one_attached :encrypted_message_data_blob
  has_one_attached :encrypted_dependency_files_blob

  validates :updated_dependency_details, presence: true
  # The grouped_update flag _must_ be true if a DependencyGroup is associated.
  validates :grouped_update, presence: true, if: -> { dependency_group_id.present? }
  validates :current_state, inclusion: { in: PendingPullRequestStateMachine.states.map(&:to_s) }

  delegate :can_transition_to?, :transition_to!, :transition_to,
           :last_transition, to: :state_machine
  delegate :multi_ecosystem_update?, :multi_ecosystem_config, :multi_ecosystem_config_id, to: :update_job

  serialize :updated_dependency_details, coder: JSON

  after_initialize :set_defaults

  LOG_PREFIX = "Failed to create pull request:"

  # rubocop:disable Metrics/MethodLength
  def can_create_pull_request?
    if updated_dependency_files.nil?
      Dependabot::Logger.info("#{LOG_PREFIX} there are no dependency files")
      increment_metric(
        "pending_pull_request.updated_dependency_files_expired_on_s3"
      )
      return false
    end

    if update_job.update_config.in_state?(:deleted)
      Dependabot::Logger.info("#{LOG_PREFIX} update_config is deleted")
      increment_metric(
        "pending_pull_request.update_config_deleted"
      )
      return false
    end

    if update_job.update_config.repo.account.in_state?(:inactive)
      Dependabot::Logger.info("#{LOG_PREFIX} account #{update_job.update_config.repo.account.id} inactive")
      increment_metric(
        "pending_pull_request.account_inactive"
      )
      return false
    end

    true
  end
  # rubocop:enable Metrics/MethodLength

  def message_data
    return {} if encrypted_message_data_blob&.attachment.nil?

    @message_data ||= begin
      blob = encrypted_message_data_blob.download
      JSON.parse(encrypted_box.decrypt(Base64.strict_decode64(blob)))
    end
  end

  def message_data=(message_data)
    ciphertext = Base64.strict_encode64(encrypted_box.encrypt(message_data.to_json))
    encrypted_message_data_blob.attach(
      io: StringIO.new(ciphertext),
      filename: id,
      content_type: "application/json",
      identify: false,
    )
  end

  def updated_dependency_files # rubocop:disable Metrics/MethodLength
    @updated_dependency_files ||=
      begin
        raise DependencyFilesNotFound if encrypted_dependency_files_blob&.attachment.nil?

        blob = encrypted_dependency_files_blob.download
        encoding = Dependabot::DependencyFile::ContentEncoding::UTF_8
        files = JSON.parse(encrypted_box.decrypt(Base64.strict_decode64(blob)))
        files = files.map(&:symbolize_keys)
        files.map do |file_data|
          dep = Dependabot::DependencyFile.new(
            name: file_data.fetch(:name),
            content: file_data.fetch(:content),
            directory: file_data.fetch(:directory),
            type: file_data.fetch(:type),
            deleted: file_data.fetch(:deleted, false),
            content_encoding: file_data.fetch(:content_encoding, encoding),
            symlink_target: file_data.fetch(:symlink_target, nil),
          )

          dep.mode = file_data.fetch(:mode, nil)
          dep
        end
      end
  end

  def updated_dependencies
    updated_dependencies = updated_dependency_details.map(&:deep_symbolize_keys)
    updated_dependencies.map { |dep| Dependabot::Dependency.new(**dep) }
  end

  def dependency_group
    return nil unless grouped_update?
    return super if dependency_group_id.present?

    DependencyGroup.new(
      name: update_job.package_manager,
      rules: {
        "patterns" => "*",
      },
    )
  end

  #######################
  # State machine setup #
  #######################

  def state_machine
    @state_machine ||=
      PendingPullRequestStateMachine.new(
        self,
        association_name: :pending_pull_request_transitions,
        transition_class: PendingPullRequestTransition,
      )
  end

  def telemetry_attributes
    update_job.telemetry_attributes.merge(
      "gh.dependabot_api.pending_pull_request.id": id,
      "gh.dependabot_api.pending_pull_request.grouped_update": grouped_update?,
    ).merge(multi_ecosystem_telemetry_attributes)
  end

  def multi_ecosystem_telemetry_attributes
    multi_ecosystem_config_id_attribute =
      if multi_ecosystem_update?
        { "gh.dependabot_api.pending_pull_request.multi_ecosystem_config_id": multi_ecosystem_config&.id }
      else
        {}
      end

    {
      "gh.dependabot_api.pending_pull_request.multi_ecosystem_update": multi_ecosystem_update?,
    }.merge(multi_ecosystem_config_id_attribute)
  end

  def increment_metric(name, tags: {})
    update_job.increment_metric(name, tags: metric_tags.merge(tags))
  end

  def metric_tags
    {
      grouped_update: grouped_update?,
    }
  end

  private

  def encrypted_box
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    RbNaCl::SimpleBox.from_secret_key(token)
  end

  def set_defaults
    return unless has_attribute?(:current_state) && self[:current_state].nil?

    # set the attribute directly to avoid interactions with the state machine
    self[:current_state] = PendingPullRequestStateMachine.initial_state
  end
end
