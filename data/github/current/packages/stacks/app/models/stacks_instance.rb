# typed: false
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class StacksInstance < ApplicationRecord::Domain::Stacks
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests

  # rubocop:todo Rails/InverseOf
  has_many :stacks_plan, foreign_key: "instance_id",
  class_name: "StacksPlan", dependent: :destroy

  has_many :stacks_flow, foreign_key: "instance_id",
  class_name: "StacksFlow", dependent: :destroy

  has_many :stacks_step, foreign_key: "instance_id",
  class_name: "StacksSteps::Step", dependent: :destroy

  has_many :stacks_status, foreign_key: "instance_id",
  class_name: "StacksStatus", dependent: :destroy
  # rubocop:enable Rails/InverseOf

  belongs_to :actor, class_name: "User"

  belongs_to :instance_repository, class_name: "Repository"
  belongs_to :template_repository, class_name: "Repository"

  enum :status, {
    not_started: 0,
    input_capture: 1,
    in_progress: 2,
    success: 3,
    failed: 4,
    configured: 5
  }

  SUCCESS = "success"
  FAILED = "failed"
  IN_PROGRESS = "in_progress"
  INPUT_CAPTURE = "input_capture"
  NOT_STARTED = "not_started"
  CONFIGURED = "configured"

  # lock will be released as soon as the plan execution is completed
  # setting the max timeout, so all the steps in the plan will be completed before releasing the lock
  # default timeout is 60 seconds
  LOCK_TIMEOUT = 20.minutes
  STATUS_METRIC = "status"
  SUCCESS_TAG = "success"
  ERROR_TAG = "error"

  def submit_plan(plan)
    # acquire a redis based mutex lock to prevent multiple plans from running on same instance
    # release the lock only when the plan is completed (success / failed) in update_status method
    # refer to lib/github/redis/mutex.rb for more details
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do |span|
      acquire_lock
      begin
        actor_id = plan.actor_id

        actor = User.find(actor_id)
        orchestrator = StacksOrchestrator.new(self.id, self.instance_repository_id, plan, actor)
        orchestrator.run
        push_instance_metrics STATUS_METRIC, __callee__, SUCCESS_TAG
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
        raise Errors::StacksInstanceRunTimeError.new("Plan submission failed: #{e.message}")
      end
      span.add_attributes("actor_id" => actor.id, "target_repo_id" => self.instance_repository_id)
      get_status
    end
  end

  after_initialize :validate, if: :new_record?
  validate :template_ref_should_be_valid

  def validate
    if self.template_repo.nil?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("template_repo is required!")
    end

    if self.owner_id.nil?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("owner_id is required!")
    end

    if self.actor_id.nil?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("actor_id is required!")
    end

    unless Repository.where(id: self.instance_repository_id).exists?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Invalid instance repository id")
    end

    unless Repository.where(id: self.template_repository_id).exists?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Invalid template repository id")
    end

    validate_repo(self.template_repo, "template_repo")

    unless User.where(id: owner_id).exists?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Invalid owner_id!")
    end

    unless User.where(id: actor_id).exists?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Invalid actor_id!")
    end
  end

  def template_ref_should_be_valid
    template_repo = Repository.find_by_id(self.template_repository_id)
    unless template_repo.refs.exist?(self.template_ref)
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Invalid template release")
    end
  end

  def validate_repo(repo_name, repo_type)
    unless repo_name =~ Repository::NAME_WITH_OWNER_PATTERN
      push_instance_metrics STATUS_METRIC, "validate", ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Invalid #{repo_type} name format, should be owner/repo_name")
    end

    owner_login, repo_name = repo_name.split("/")
    unless Repository.where(name: repo_name, owner_login: owner_login).exists?
      push_instance_metrics STATUS_METRIC, "validate", ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Invalid #{repo_type} name!")
    end
  end

  def save_inputs(inputs_hash)
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do
      if inputs_hash.nil?
        push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
        raise Errors::StacksInstanceValidationError.new("inputs_hash is required!")
      end

      self.inputs = inputs_hash.to_json
      save

      input_capture!
      push_instance_metrics STATUS_METRIC, __callee__, SUCCESS_TAG
    end
  end

  def self.get(repo_id)
    instance = StacksInstance.find_by(instance_repository_id: repo_id)
    if instance.nil?
      Metrics.push_metric Metrics::INCREMENT, Component::INSTANCE, __callee__, STATUS_METRIC, tags: ["action:#{ERROR_TAG}"]
      raise Errors::StacksInstanceNotFoundError.new("Stack instance not found!")
    end

    instance
  end

  def self.exists?(repo_id)
    instance = StacksInstance.find_by(instance_repository_id: repo_id)
    !instance.nil?
  end

  def get_status
    return StacksInstanceStatus.from_json(self.reload.status_details) unless self.status_details.nil?
    StacksInstanceStatus.new(instance_id: self.id, plan_id: nil, status: NOT_STARTED, statuses: [])
  end

  def update_status
    status = StacksOrchestrator.get_status(self.id)
    current_status = get_status
    if status != current_status
      if status.failed_step_group.nil? && !current_status.failed_step_group.nil?
        status.failed_step_group = current_status.failed_step_group
      end

      self.status_details = status.to_json
      self.save

      # Adding this to give time to Ui to load
      cleaning_up?(status.step_statuses)

      notify_live_status(status)
    end

    if completed?
      # release mutex lock if instance status is completed
      release_lock
      push_instance_metrics STATUS_METRIC, __callee__, status.status
    end
  end

  def cleaning_up?(step_statuses)
    if step_statuses.length == 4
      sleep 7 unless Rails.env.test?
    end
  end

  def in_progress!
    instance_status_details = get_status
    instance_status_details.status = IN_PROGRESS
    self.status_details = instance_status_details.to_json
    save
  end

  def input_capture!
    instance_status_details = get_status
    instance_status_details.status = INPUT_CAPTURE
    self.status_details = instance_status_details.to_json
    save
  end

  # Update state to configured only if instance status is success
  # In all other cases, allow user to configure repo or retry
  def configured!
    unless success?
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceValidationError.new("Cannot set status to configured when current status is not success")
    end

    instance_status_details = get_status
    instance_status_details.status = CONFIGURED
    self.status_details = instance_status_details.to_json
    self.save
  end

  def overall_status
    get_status.status
  end

  def completed?
    success? || failed?
  end

  def success?
    overall_status == SUCCESS
  end

  def failed?
    overall_status == FAILED
  end

  def in_progress?
    overall_status == IN_PROGRESS
  end

  def not_started?
    overall_status == NOT_STARTED
  end

  def started?
    overall_status != NOT_STARTED
  end

  def input_capture?
    overall_status == INPUT_CAPTURE
  end

  def configured?
    overall_status == CONFIGURED
  end

  private_class_method :validate

  private

  def notify_live_status(stacks_instance_status)
    data = {}
    data[:timestamp] = Time.now.to_i
    data[:reason] = "stack instance ##{id} updated"
    channel_id = GitHub::WebSocket::Channels.stacks_instance_status(stacks_instance_status)
    GitHub::WebSocket.notify_stacks_channel(self, channel_id, data)
  end

  def get_mutex
    lock_key = "stack_instance:#{self.id}"
    GitHub::Redis::Mutex.new(lock_key, timeout: LOCK_TIMEOUT)
  end

  def acquire_lock
    mutex = get_mutex
    begin
      mutex.lock
    rescue GitHub::Redis::Mutex::LockError
      push_instance_metrics STATUS_METRIC, __callee__, ERROR_TAG
      raise Errors::StacksInstanceAlreadyRunningError.new("A Plan is already running for stack instance: #{self.id}")
    end
  end

  def release_lock
    mutex = get_mutex
    mutex.unlock!
  end

  def push_instance_metrics(metric_name, operation, status)
    Metrics.push_metric Metrics::INCREMENT, Component::INSTANCE, operation, metric_name, tags: ["action:#{status}"]
  end
end
