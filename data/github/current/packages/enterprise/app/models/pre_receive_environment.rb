# typed: true
# frozen_string_literal: true

class PreReceiveEnvironment < ApplicationRecord::Domain::PreReceive
  include Instrumentation::Model
  include GitHub::Validations

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::PreReceiveEnvironment

  validates_uniqueness_of :name, case_sensitive: false
  validates_presence_of :name
  validates :name, unicode3: true
  validates :image_url, presence: true, length: { maximum: 255 }

  enum :download_state, {
    not_started: 0,
    in_progress: 1,
    success: 2,
    failed: 3,
  }
  validates :download_state, presence: true

  # rubocop:todo Rails/InverseOf
  has_many :hooks,
    class_name: "PreReceiveHook",
    foreign_key: "environment_id",
    dependent: :restrict_with_exception
  # rubocop:enable Rails/InverseOf

  before_update :can_update?

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy
  before_destroy :ensure_destroyable, :queue_delete_from_filesystem
  after_commit :queue_download_if_needed

  after_save :sync_download_state_if_needed

  validate :not_default_environment?, on: :update

  def instrument_create
    instrument :create
  end

  def instrument_update
    instrument :update
  end

  def instrument_destroy
    instrument :destroy
  end

  def event_prefix
    :pre_receive_environment
  end

  def event_payload
    { event_prefix => self }
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  # The number of associated PreReceiveHooks.
  #
  # Returns the Integer hooks count.
  def hooks_count
    return @hooks_count if defined?(@hooks_count)
    @hooks_count = hooks.size
  end
  attr_writer :hooks_count

  # We don't want to allow updating name or image_url when there is a download in progress
  def can_update?
    if self.download_in_progress? && self.changes.keys.include?("image_url")
      errors.add(:base, "Cannot update environment when download is in progress")

      throw :abort
    end
    true
  end

  def can_destroy?
    if hooks.any?
      errors.add(:base, "Cannot delete environment that has hooks")
      return false
    end
    if download_in_progress?
      errors.add(:base, "Cannot delete environment when download is in progress")
      return false
    end
    not_default_environment?
  end

  def download_succeeded?
    success?
  end

  def download_failed?
    failed?
  end

  def download_in_progress?
    in_progress?
  end

  def start_download(start_time = Time.now)
    update! downloaded_at: start_time,
                       download_state: :in_progress,
                       download_message: nil
  end

  def download_succeeded(checksum)
    update! download_state: :success,
                       checksum: checksum
  end

  def download_failed(download_message = nil)
    update! download_state: :failed, download_message: download_message
  end

  def queue_download_if_needed
    queue_download if !download_in_progress? && previous_changes.key?("image_url")
  end

  def can_queue_download?
    if download_in_progress?
      errors.add(:base, "Can not start a new download when a download is in progress")
      return false
    end
    not_default_environment?
  end

  def queue_download
    return unless can_queue_download?
    instrument :download
    PreReceiveEnvironmentDownloadJob.perform_later(id.to_s)
  end

  def queue_delete_from_filesystem
    PreReceiveEnvironmentDeleteJob.perform_later(id.to_s)
  end

  # Syncs the environment download state if the user has it open in a browser.
  def sync_download_state
    data = {
      message: "#{self.download_display_message}",
    }
    channel = GitHub::WebSocket::Channels.pre_receive_environment_state(self)
    GitHub::WebSocket.notify_pre_receive_environment_channel(self, channel, data)
  end

  def download_display_message
    case self.download_state
    when "not_started"
      "Download has not started"
    when "in_progress"
      "Download is in progress"
    when "success"
      "Environment downloaded and ready"
    when "failed"
      "Download failed. #{self.download_message}"
    end
  end

  def default_environment?
    self == self.class.default
  end

  def self.sorted_by(order = nil, direction = nil)
    direction = "DESC" == "#{direction}".upcase ? "DESC" : "ASC"
    order = "id" unless order == "name"
    order([order, direction].join(" "))
  end

  def self.default
    @default_env ||= PreReceiveEnvironment.find_by(image_url: "githubenterprise://internal")
  end

  private

  def sync_download_state_if_needed
    sync_download_state if saved_change_to_download_state?
  end

  def not_default_environment?
    if default_environment?
      errors.add(:base, "Cannot modify or delete the default environment")
      return false
    end
    true
  end

  def ensure_destroyable
    throw :abort unless can_destroy?
  end
end
