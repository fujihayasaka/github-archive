# typed: true
# frozen_string_literal: true

require "github-launch"

class Actions::LargerRunner
  include ActiveModel::Validations

  class LargerRunnerServiceError < Actions::ServiceError; end

  class ImageKey
    include ActiveModel::Validations

    attr_accessor :source, :id, :version

    validates :source, presence: true
    validates :id, presence: true
    validates :version, presence: true

    def initialize(source:, id: "", version: "latest")
      @source = source
      @id = id
      @version = version
    end
  end

  class PublicIP
    attr_reader :enabled, :prefix, :length

    def initialize(enabled: false, prefix: nil, length: 0)
      @enabled = enabled
      @prefix = prefix
      @length = length
    end

    def self.from_rpc_collection(entities)
      entities.map { |entity| from_rpc_object(entity) }
    end

    private_class_method def self.from_rpc_object(entity)
      return nil if entity.nil?

      new(
        enabled: entity.enabled,
        prefix: entity.prefix,
        length: entity.length,
      )
    end
  end

  class PublicIPSettings
    INCREASED_UPPER_PUBLIC_IP_LIMIT_200 = 200
    INCREASED_UPPER_PUBLIC_IP_LIMIT_50 = 50
    STANDARD_UPPER_PUBLIC_IP_LIMIT = 10

    def self.get_customer_tier(entity)
      TrustTiers::Tier.for_billable_owner(entity).tier
    end

    def self.graceful_days_for(entity)
      tier_map = {
        TrustTiers::Tier::TRUSTED => 7,
        TrustTiers::Tier::NEUTRAL => 3,
        TrustTiers::Tier::UNTRUSTED => 1,
      }

      tier = get_customer_tier(entity)
      days = tier_map.fetch(tier)
    end

    def self.graceful_period_for(entity)
      graceful_days_for(entity) + 3 # after disabling public IP, the resource is still in Azure for 3 days more. So if customer upgraded back and enables Public IP - the same resource will be used
    end

    def self.max_non_used_days_for(entity)
      customer_tier = get_customer_tier(entity)
      tier_map = {
        TrustTiers::Tier::TRUSTED => 90,
        TrustTiers::Tier::NEUTRAL => 60,
        TrustTiers::Tier::UNTRUSTED => 31,
      }

      last_used_day_count = tier_map.fetch(customer_tier)
    end
  end

  attr_reader :id, :name, :state, :platform, :runner_count, :maximum_runners, :is_dev, :machine_spec_id, :public_ips, :status, :image_sas_uri, :machine_spec, :last_active_on, :unavailable_runner_count, :is_public_ip_ready, :persistent_os_disk, :error_code

  sig { returns(T.nilable(ImageKey)) }
  attr_accessor :image

  attr_accessor :group, :group_name, :inherited, :labels, :runner_group_id, :is_public_ip_enabled

  # maximum_runners
  # See larger-runners.ts for client-side validations of max_runners
  MAX_RUNNERS_LOWER_LIMIT = 1
  MAX_RUNNERS_UPPER_LIMIT = 1000
  MAX_GPU_RUNNERS_UPPER_LIMIT = 20
  MAX_GPU_RUNNERS_UPPER_INCREASED_LIMIT = 100 # TODO: make it a default one after going to public beta
  MAX_RUNNERS_DEFAULT = 50

  # TODO: We should consider refactoring our code in create and update in the larger_runners_controller so that the instances created are consistent with each other.
  # Refactoring our larger_runners_controller code will allow us to have a more consistent validation pattern.

  # We need allow_nil to be true to allow our custom hosted runner instance to be valid when created in the create method in larger_runners_controller.
  # In our create method in larger_runners_controller, we don't pass a :id attribute thus making it nil.
  validates :id, numericality: { only_integer: true }, allow_nil: true

  # Match server side validation in actions-dotnet/Runner/Service/Server/ArgumentValidation#CheckScaleSetName
  validates :name, presence: true, format: { with: /[a-zA-Z0-9\-\_.]{1,64}/ }

  # Valid states can be found in Launch: https://github.com/github/launch/blob/master/services/deploy/largerrunners/convertfromruntime.go#L43-L50
  # We need allow_nil to be true to allow our custom hosted runner instance to be valid when created in the create and update method in larger_runners_controller.
  # In our create and update method in larger_runners_controller, we don't pass a :state attribute thus making it nil.
  validates :state, inclusion: { in: [:Provisioning, :Ready, :Deleting, :ShutdownBilling, :ShutdownSpammy, :ShutdownNetwork, :Stuck] }, allow_nil: true

  # We need allow_nil to be true to allow our custom hosted runner instance to be valid when created in the update method in larger_runners_controller.
  # In our update method in larger_runners_controller, we don't pass a :platform attribute thus making it nil.
  validates :platform, inclusion: { in: %w[linux-x64 win-x64 linux-arm64 win-arm64] }, allow_nil: true

  # We cannot validate the runner group by using the same logic as in runner_groups_controllers.rb because we don't have access to the owner
  validates :runner_group_id, presence: true, numericality: { only_integer: true }

  validates :is_dev, inclusion: { in: [true, false] }

  # We validate image key only on create because we don't allow to update image for existing pools
  validate :validate_image_key, on: :create

  # We get machine_spec_ids from Launch via "larger_runner_sizes" in larger_runners_helper.rb
  validates :machine_spec_id, presence: true

  validates :is_public_ip_enabled, inclusion: { in: [true, false] }

  # Status is equivalent to the state so we can use the same validations
  # We need allow_nil to be true to allow our custom hosted runner instance to be valid when created in the create and update method in larger_runners_controller.
  # In our create and update method in larger_runners_controller, we don't pass a :status attribute thus making it nil.
  validates :status, inclusion: { in: [:Provisioning, :Ready, :Deleting, :ShutdownBilling, :ShutdownSpammy, :ShutdownNetwork, :Stuck] }, allow_nil: true

  validates :inherited, inclusion: { in: [true, false] }

  # Upper limit is set to higher value in Rails validation--use `maximum_runners_valid?` to use correct value given ff
  validates :maximum_runners, numericality: { greater_than_or_equal_to: MAX_RUNNERS_LOWER_LIMIT, less_than_or_equal_to: MAX_RUNNERS_UPPER_LIMIT }

  validates :unavailable_runner_count, numericality: { greater_than_or_equal_to: 0 }

  validates :persistent_os_disk, inclusion: { in: [true, false] }

  def initialize(name: nil, runner_group_id: nil, group_name: nil, id: nil, state: nil, platform: nil, runner_count: 0, maximum_runners: MAX_RUNNERS_DEFAULT, is_dev: false, image: nil, machine_spec_id: nil, is_public_ip_enabled: false, is_public_ip_ready: false, labels: [], inherited: false, image_sas_uri: nil, public_ips: [], machine_spec: nil, last_active_on: nil, unavailable_runner_count: 0, persistent_os_disk: false, error_code: nil)
    @id = id
    @name = name
    @state = state
    @platform = platform
    @runner_group_id = runner_group_id
    @group_name = group_name
    @runner_count = runner_count
    @maximum_runners = maximum_runners
    @is_dev = is_dev
    @image = image
    @machine_spec_id = machine_spec_id
    @is_public_ip_enabled = is_public_ip_enabled
    @is_public_ip_ready = is_public_ip_ready
    @image_sas_uri = image_sas_uri
    @public_ips = public_ips
    @labels = labels
    @status = state
    @inherited = inherited
    @machine_spec = machine_spec
    @last_active_on = last_active_on
    @unavailable_runner_count = unavailable_runner_count
    @persistent_os_disk = persistent_os_disk
    @error_code = error_code
  end

  sig { params(owner: T.any(Organization, Business), pool_id: Integer).returns(T.nilable(Actions::LargerRunner)) }
  def self.get_larger_runner(owner, pool_id:)
    resp = Launch::Twirp::larger_runners_client.get_pool(owner, pool_id: pool_id)

    pr = from_rpc_object(resp.value&.pool)

    return nil unless pr.present?

    pr.set_labels
    pr
  end

  sig { params(entity: T.any(Business, User, Repository), owner: T.nilable(T.any(Organization, Business)), is_public_ip_enabled: T.nilable(T::Boolean), propagate_errors: T::Boolean).returns(T::Array[Actions::LargerRunner]) }
  def self.larger_runners_for(entity:, owner: nil, is_public_ip_enabled: nil, propagate_errors: false)
    if owner.nil?
      if entity.is_a?(Organization) || entity.is_a?(Business)
        owner = entity
      else
        owner = entity.owner
      end
    end

    resp = Launch::Twirp::larger_runners_client.list_pools(
      owner,
      entity: entity,
      is_public_ip_enabled: is_public_ip_enabled
    )

    if propagate_errors && !resp.call_succeeded?
      raise LargerRunnerServiceError.new("list_pools failed", status: resp.status, options: resp.options)
    end

    larger_runners = from_rpc_collection(resp.value&.pools || [])
    larger_runners.each do |pr|
      pr.set_labels
    end

    larger_runners
  end

  sig { params(owner: T.any(Organization, Business), pool_id: Integer).returns(T::Array[Integer]) }
  def self.get_check_runs_for_pool(owner, pool_id:)
    resp = Launch::Twirp::larger_runners_client.list_pool_agents(owner, pool_id: pool_id)

    check_run_ids = check_run_ids_from_rpc_collection(resp.value&.agents)

    return [] unless check_run_ids.present?
    check_run_ids
  end

  sig { params(entity: T.untyped).returns(T.nilable(Actions::LargerRunner)) }
  def self.from_rpc_object(entity)
    return nil if entity.nil?

    new(
      id: entity.id,
      name: entity.name,
      state: entity.state,
      platform: entity.platform,
      runner_group_id: entity.runner_group_id,
      group_name: entity.group_name,
      inherited: entity.inherited,
      runner_count: entity.runner_count,
      maximum_runners: entity.maximum_runners,
      image: entity.image.nil? ? nil : ImageKey.new(source: entity.image.source, id: entity.image.id, version: entity.image.version),
      machine_spec_id: entity.machine_spec_id,
      is_public_ip_enabled: entity.public_ip_enabled,
      # public ip pools could have multiple ip ranges, consider public ip ready only when all ranges are ready
      is_public_ip_ready: entity.public_ip_enabled && !entity.public_ips.any? { |ip| ip.prefix.empty? },
      public_ips: PublicIP.from_rpc_collection(entity.public_ips),
      labels: entity.labels,
      machine_spec: Actions::MachineSpec.from_rpc_object(entity.machine_spec),
      last_active_on: entity.last_active_on,
      unavailable_runner_count: entity.unavailable_runner_count,
      persistent_os_disk: entity.persistent_os_disk,
      error_code: entity.error_code,
    )
  end

  sig { params(entities: T.untyped).returns(T::Array[Actions::LargerRunner]) }
  private_class_method def self.from_rpc_collection(entities)
    # Remove nil entries, ensure single objects are returned as an array
    Array.wrap(entities.filter_map { |entity| from_rpc_object(entity) })
  end

  sig { params(collection: T.untyped).returns(T.nilable(T::Array[Integer])) }
  private_class_method def self.check_run_ids_from_rpc_collection(collection)
    return nil if collection.nil?
    collection.select { |c| c.assigned_request.present? && c.assigned_request.check_run_id.present? }.map do |c|
      Platform::Helpers::NodeIdentification.from_global_id(c.assigned_request.check_run_id)[1].to_i
    end
  end

  def inherited?
    @inherited
  end

  def runner_group(entity)
    @runner_group ||= Actions::RunnerGroup.get(entity, id: runner_group_id, include_runners: true, is_ui_read: true)
  end

  def runner_group_name(entity)
    runner_group(entity)&.name
  end

  def runner_group_path(owner_settings)
    group_id = @runner_group_id
    owner_settings.update_runner_group_path(id: group_id)
  end

  def runner_custom_image_path(owner_settings)
    image_id = T.must(@image).id
    owner_settings.runner_custom_image_path(id: image_id)
  end

  def is_in_editable_state?
    state == :Ready
  end

  def is_in_deleting_state?
    state == :Deleting
  end

  def is_in_provisioning_state?
    state == :Provisioning
  end

  # currently larger runners will be displayed above all other runners, so priority is negative
  def view_priority
    case state
    when :Provisioning then -6
    when :ShutdownSpammy then -5
    when :ShutdownBilling then -4
    when :ShutdownNetwork then -3
    when :Ready then -2
    when :Deleting then -1
    else
      0
    end
  end

  def operating_system
    case platform
    when "linux-x64"
      :linux
    when "win-x64"
      :windows
    end
  end

  def set_labels
    labels = @labels.map { |l| GitHub::Launch::Services::Selfhostedrunners::Label.new(name: l, id: -1, type: "user") }

    if @labels.none?(name)
      labels.unshift(GitHub::Launch::Services::Selfhostedrunners::Label.new(name: name, id: -1, type: "system"))
    end
    @labels = labels
  end

  def validate_image_key
    i = image
    if i.nil?
      errors.add(:image, "is required")
    elsif [:Curated, :Marketplace].include?(i.source)
      if i.id.blank?
        errors.add(:image, "requires image name for curated and marketplace image sources")
      end
    elsif i.source == :Custom
      if image_sas_uri.blank? && i.id.blank?
        errors.add(:image, "requires image_sas_uri for custom image source")
      end
    else
      errors.add(:image, "source is required")
    end
  end

  def maximum_runners_valid?(gpu_limit:)
    return maximum_runners >= MAX_RUNNERS_LOWER_LIMIT && maximum_runners <= MAX_RUNNERS_UPPER_LIMIT if !machine_spec&.is_gpu_spec?

    maximum_runners >= MAX_RUNNERS_LOWER_LIMIT && maximum_runners <= gpu_limit
  end
end
