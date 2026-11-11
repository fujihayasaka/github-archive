# typed: true
# frozen_string_literal: true

module Codespaces
  class PolicyConstraint < ApplicationRecord::Domain::Policies
    CODESPACES_ALLOWED_MACHINE_TYPES = "codespaces.allowed_machine_types"
    CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS = "codespaces.allowed_port_privacy_settings"
    CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT = "codespaces.allowed_maximum_idle_timeout" # in minutes
    CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD = "codespaces.allowed_maximum_retention_period" # in minutes
    CODESPACES_ALLOWED_BASE_IMAGES = "codespaces.allowed_base_images"
    CODESPACES_ALLOWED_MAXIMUM_CREATIONS = "codespaces.allowed_maximum_creations"
    CODESPACES_HOST_SETUP = "codespaces.host_setup"
    DOCKER_REGEX = "^(?:(?=[^:/]{1,253})(?!-)[a-zA-Z0-9-]{1,63}(?<!-)(?:.(?!-)[a-zA-Z0-9-]{1,63}(?<!-))*(?::[0-9]{1,5})?/)?((?![._-])(?:[a-z0-9._-]*)(?<![._-])(?:/(?![._-])[a-z0-9._-]*(?<![._-]))*)(?::(?![.-])[a-zA-Z0-9_.-]{1,128})?$"
    CODESPACES_ALLOWED_ENTITIES = "codespaces.allowed_entities"
    CODESPACES_NETWORK_CONFIGURATION = "codespaces.network_configuration"

    class AllowableValue
      attr_reader :name, :display_name, :display_description
      def initialize(name:, display_name:, display_description: nil)
        @name = name
        @display_name = display_name
        @display_description = display_description
      end
    end

    enum :name, {
      CODESPACES_ALLOWED_MACHINE_TYPES => 0,
      CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS => 1,
      CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT => 2,
      CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD => 3,
      CODESPACES_ALLOWED_BASE_IMAGES => 4,
      CODESPACES_ALLOWED_ENTITIES => 5,
      CODESPACES_ALLOWED_MAXIMUM_CREATIONS => 6,
      CODESPACES_HOST_SETUP => 7,
      CODESPACES_NETWORK_CONFIGURATION => 8,
    }

    enum :value_type, [ # Need the type_ prefixes here in enum values to avoid conflicting generated methods.
      TYPE_ENABLED        = :type_enabled,
      TYPE_MAXIMUM        = :type_maximum,
      TYPE_MINIMUM        = :type_minimum,
      TYPE_ALLOWED_VALUES = :type_allowed_values,
      TYPE_ALLOWED_VALUE  = :type_allowed_value,
      TYPE_PARAMS         = :type_params,
    ]

    CODESPACES_NETWORK_CONFIGURATION_TEXT = "Network configuration"

    IDLE_TIMEOUT_MAXIMUM_VALUE = Codespaces::Vscs::MAX_IDLE_TIME / 1.minute
    IDLE_TIMEOUT_MINIMUM_VALUE = Codespaces::Vscs::MIN_IDLE_TIME / 1.minute
    RETENTION_PERIOD_MINIMUM_VALUE = 0

    # Maps each constraint name to a hash of its configuration.
    # type: one of the value_type constants enumerated above.
    # display_name: Used for labelling the constraint in the UI.
    # allowable_values_options: Array of AllowableValue objects which must include a :name attr representing the underlying value for the constraint,
    #                        and a :display_name attr for labelling in the UI. Optionally, an :display_description attr can be provided for additional UI context.
    # display_allowed_value_proc: An optional proc for type_allowed_values, that maps a given allowed value to its display equivalent.
    # allowed_values_wildcard: When specified and true, supports values ending with '*' as a wildcard matcher when comparing against or between sets of allowed_values.
    CONSTRAINT_CONFIGURATION = {
      CODESPACES_ALLOWED_MACHINE_TYPES => {
        name: CODESPACES_ALLOWED_MACHINE_TYPES,
        display_name: "Machine types",
        type: TYPE_ALLOWED_VALUES,
        allowable_values_options: Codespaces::Skus::SKUS.values.sort_by(&:cpus).map do |sku|
          AllowableValue.new(name: sku.name.to_s, display_name: sku.display_cpus, display_description: "#{sku.display_memory} • #{sku.display_storage}")
        end,
        display_allowed_value_proc: proc do |value, policy_owner|
          sku = Codespaces::Skus::SKUS.fetch(value.to_sym, nil)
          next unless sku&.allowable_by_policy_owner?(policy_owner)
          sku.display_cpus
        end,
        sort_allowed_values_proc: proc do |allowed_values|
          skus = allowed_values.map { |sku_name| Codespaces::Skus::SKUS.fetch(sku_name.to_sym, nil) }.compact
          Codespaces::Skus.resource_ascending_skus(skus).map { |s| s.name.to_s }
        end,
        description: "Set what machine types repository codespaces have access to."
      },
      CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS => {
        name: CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS,
        display_name: "Port privacy settings",
        type: TYPE_ALLOWED_VALUES,
        allowable_values_options: [
          AllowableValue.new(name: Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG], display_name: "Org", display_description: "Authenticated org members"),
          AllowableValue.new(name: Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC], display_name: "Public", display_description: "Anyone with the link"),
        ],
        description: "Set what visibility options users are able to forward ports with."
      },
      CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT => {
        name: CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT,
        display_name: "Maximum idle timeout",
        type: TYPE_MAXIMUM,
        description: "Set the maximum idle time that codespaces will stay active before they’re stopped.",
        maximum_allowable_value: IDLE_TIMEOUT_MAXIMUM_VALUE,
        minimum_allowable_value: IDLE_TIMEOUT_MINIMUM_VALUE,
      },
      CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD => {
        name: CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD,
        display_name: "Maximum retention period",
        type: TYPE_MAXIMUM,
        description: "Set the maximum time that inactive codespaces will be available before they’re deleted.",
        maximum_allowable_value: ActiveSupport::Duration.build(Codespace::MAX_RETENTION_PERIOD * 60).in_days.to_i,
        minimum_allowable_value: RETENTION_PERIOD_MINIMUM_VALUE,
      },
      CODESPACES_ALLOWED_BASE_IMAGES => {
        name: CODESPACES_ALLOWED_BASE_IMAGES,
        display_name: "Base images",
        type: TYPE_ALLOWED_VALUES,
        custom_allowed_values: true,
        allowed_values_wildcard: true,
        description: "Set allowed base images for your codespaces. Supports wildcard syntax (*) as the last character to allow all images matching a specific prefix (e.g. ghcr.io/*).",
        input_placeholder: "Enter an image URL, optionally ending with a wildcard (e.g. ghcr.io/*)",
      },
      CODESPACES_ALLOWED_ENTITIES => {
        name: CODESPACES_ALLOWED_ENTITIES,
        display_name: "Entities",
        type: TYPE_ALLOWED_VALUE,
        allowable_values_options: [
          AllowableValue.new(name: Codespaces::EntityPolicy::ALL, display_name: Codespaces::EntityPolicy::ALL),
          AllowableValue.new(name: Codespaces::EntityPolicy::SELECTED, display_name: Codespaces::EntityPolicy::SELECTED),
          AllowableValue.new(name: Codespaces::EntityPolicy::NONE, display_name: Codespaces::EntityPolicy::NONE),
        ],
        hidden: true,
      },
      CODESPACES_ALLOWED_MAXIMUM_CREATIONS => {
        name: CODESPACES_ALLOWED_MAXIMUM_CREATIONS,
        display_name: "Maximum codespaces per user",
        type: TYPE_MAXIMUM,
        global_target_only: true,
        description: "Restrict the total number of codespaces (billable to the policy owner) that a user can have at once",
        maximum_allowable_value: Codespaces::Tier::CODESPACES_PER_USER,
        minimum_allowable_value: 1,
        disabled_note: "Note: This constraint cannot be applied to a policy that targets selected repositories",
      },
      CODESPACES_HOST_SETUP => {
        name: CODESPACES_HOST_SETUP,
        display_name: "Host setup",
        type: TYPE_PARAMS,
        required_keys: %w[
          repo
          branch
          path
        ],
        isolate_constraint_to_a_single_policy: true,
        description: "Define a script or executable to run on codespaces virtual machines before the development environment is created."
      },
      CODESPACES_NETWORK_CONFIGURATION => {
        name: CODESPACES_NETWORK_CONFIGURATION,
        display_name: CODESPACES_NETWORK_CONFIGURATION_TEXT,
        type: TYPE_PARAMS,
        required_keys: %w[
          id
          name
        ],
        isolate_constraint_to_a_single_policy: true,
        description: "Select the network configuration for the target repositories."
      },
    }.freeze

    belongs_to :policy_group
    has_many :policy_group_memberships, through: :policy_group

    validates :name, presence: true, uniqueness: { scope: :policy_group_id }, inclusion: { in: CONSTRAINT_CONFIGURATION.keys }
    validates :value_type, presence: true, inclusion: { in: value_types.keys }
    validates :enabled_value, inclusion: { in: [true, false] }, allow_nil: true
    validates :maximum_value, numericality: { only_integer: true }, allow_nil: true
    validates :minimum_value, numericality: { only_integer: true }, allow_nil: true

    validates :policy_group, presence: true
    validate :one_appropriate_value_type
    validate :no_unexpected_allowed_values, if: -> { T.bind(self, PolicyConstraint); has_allowed_values? }
    validate :validate_maximum_value_is_within_limits_for_idle_timeout, if: -> { name == CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT }
    validate :validate_maximum_value_is_within_limits_for_retention_period, if: -> { name == CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD }
    validate :validate_container_image_for_allowed_base_image, if: -> { name == CODESPACES_ALLOWED_BASE_IMAGES }
    validate :validate_length_allowed_value, if: -> { T.bind(self, PolicyConstraint); value_type == TYPE_ALLOWED_VALUE.to_s }
    validate :validate_params, if: -> { T.bind(self, PolicyConstraint); value_type == TYPE_PARAMS.to_s }
    validate :validate_host_setup_config, if: -> { name == CODESPACES_HOST_SETUP }
    validate :validate_network_configuration, if: -> { name == CODESPACES_NETWORK_CONFIGURATION }

    before_validation :set_value_type, on: :create

    after_commit :instrument_creation, on: :create
    after_commit :instrument_destroy, on: :destroy

    # Constraint configuration with owner-specific context layered on top.
    # Today this filters allowable values, lowers a maximum allowable value, and possibly marks a constraint disbaled.
    def self.config_for_policy_owner(owner)
      config = CONSTRAINT_CONFIGURATION.deep_dup
      config.keys.each do |name|
        if config[name][:allowable_values_options]
          config[name][:allowable_values] = allowable_values_for_policy_owner(name, owner)
        end

        if config[name][:maximum_allowable_value]
          config[name][:maximum_allowable_value] = maximum_allowable_value_for_policy_owner(name, owner)
        end

        config[name][:disabled] = case name
        when CODESPACES_HOST_SETUP
          !owner.feature_flag_enabled?(:codespaces_host_setup_policy, default: false) || !owner.in_codespaces_salus_beta?
        when CODESPACES_NETWORK_CONFIGURATION
          !(owner.is_a?(Organization) && Codespaces::OrgPolicy.new(user: nil, org: owner).org_admin_can_configure_private_networking?)
        else
          false
        end
      end
      config
    end

    def self.allowable_values_for_policy_owner(name, owner)
      allowable_values = CONSTRAINT_CONFIGURATION.dig(name, :allowable_values_options)
      if name == CODESPACES_ALLOWED_MACHINE_TYPES
        allowable_values.select do |value|
          Codespaces::Skus::SKUS.fetch(value.name.to_sym, nil)&.allowable_by_policy_owner?(owner)
        end
      else
        allowable_values
      end
    end

    def self.maximum_allowable_value_for_policy_owner(name, owner)
      max_value = CONSTRAINT_CONFIGURATION.dig(name, :maximum_allowable_value)
      if name == CODESPACES_ALLOWED_MAXIMUM_CREATIONS
        return max_value if owner.is_a?(Business)
        tier = Codespaces::Tier.for_billable_owner(owner)
        Codespaces::Tier.config_for_tier(tier, owner).codespaces_per_user
      else
        max_value
      end
    end

    def value
      case CONSTRAINT_CONFIGURATION.dig(name, :type)
      when TYPE_ENABLED
        self.enabled_value
      when TYPE_MAXIMUM
        self.maximum_value
      when TYPE_MINIMUM
        self.minimum_value
      when TYPE_PARAMS
        self.params
      when TYPE_ALLOWED_VALUES, TYPE_ALLOWED_VALUE
        self.allowed_values
      end
    end

    def value=(value)
      raise "Must have set a constraint's name to set its value" unless name.present?

      case CONSTRAINT_CONFIGURATION.dig(name, :type)
      when TYPE_ENABLED
        self.enabled_value = value
      when TYPE_MAXIMUM
        self.maximum_value = value
      when TYPE_MINIMUM
        self.minimum_value = value
      when TYPE_ALLOWED_VALUES, TYPE_ALLOWED_VALUE
        self.allowed_values = value
      when TYPE_PARAMS
        if value.present?
          self.params = JSON.parse(value)
        end
      else
        raise "Unknown constraint name: #{name}"
      end
    end

    def display_name
      CONSTRAINT_CONFIGURATION.dig(name, :display_name)
    end

    def display_value
      case CONSTRAINT_CONFIGURATION.dig(name, :type)
      when TYPE_ENABLED
        enabled_value ? "Enabled" : "Disabled"
      when TYPE_MAXIMUM
        maximum_display_value
      when TYPE_MINIMUM
        minimum_value
      when TYPE_PARAMS
        if name == CODESPACES_HOST_SETUP
          "#{GitHub.url}/#{params["repo"]}/blob/#{params["branch"]}/#{params["path"]}"
        elsif name == CODESPACES_NETWORK_CONFIGURATION
          "#{params["name"]}"
        end
      when TYPE_ALLOWED_VALUES
        sort_proc = CONSTRAINT_CONFIGURATION.dig(name, :sort_allowed_values_proc) || proc { |v| v }
        allowed_list = sort_proc.call(allowed_values)
        display_proc = CONSTRAINT_CONFIGURATION.dig(name, :display_allowed_value_proc) || proc { |v, _| v }
        allowed_list = allowed_list.map { |value| display_proc.call(value, policy_group&.owner) }.join(", ")
        if allowed_list.present?
          allowed_list.truncate(120)
        else
          "No allowed values"
        end
      end
    end

    def global_target_only?
      CONSTRAINT_CONFIGURATION.dig(name, :global_target_only)
    end

    def isolate_constraint_to_a_single_policy?
      CONSTRAINT_CONFIGURATION.dig(name, :isolate_constraint_to_a_single_policy)
    end

    def audit_log_data
      { name: name, display_name: display_name, value: audit_value, display_value: display_value }
    end

    private

    # If any new value types are added here we need to validate that we are in fact sending String types here
    # Elastic Search will break if we send other value types here due to Dynamic Mapping.
    def audit_value
      case CONSTRAINT_CONFIGURATION.dig(name, :type)
      when TYPE_ENABLED
        self.enabled_value ? "Enabled" : "Disabled"
      when TYPE_MAXIMUM
        self.maximum_value.to_s
      when TYPE_MINIMUM
        self.minimum_value.to_s
      when TYPE_ALLOWED_VALUES
        self.allowed_values
      when TYPE_PARAMS
        self.params
      end
    end

    def set_value_type
      self.value_type = self.value_type.presence || CONSTRAINT_CONFIGURATION.dig(name, :type)
    end

    def maximum_display_value
      case self.name
      when CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT
        "#{maximum_value} minutes"
      when CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD
        "#{maximum_value&.minutes.in_days.to_i} days"
      else
        maximum_value
      end
    end

    def one_appropriate_value_type
      if [enabled_value, maximum_value, minimum_value, allowed_values, params].count { |v| !v.nil? } == 1
        expected_value_type = CONSTRAINT_CONFIGURATION.dig(name, :type)
        errors.add(:value_type, "Expected #{expected_value_type} value type") if value_type.to_sym != expected_value_type
        case expected_value_type
        when TYPE_ENABLED
          errors.add(:enabled_value, "Must be specified") if enabled_value.nil?
        when TYPE_MAXIMUM
          errors.add(:maximum_value, "Must be specified") if maximum_value.nil?
        when TYPE_MINIMUM
          errors.add(:maximum_value, "Must be specified") if minimum_value.nil?
        when TYPE_ALLOWED_VALUES
          errors.add(:allowed_values, "Must be an array of strings") unless allowed_values.is_a?(Array) && allowed_values.all? { |v| v.is_a?(String) }
        when TYPE_PARAMS
          errors.add(:params, "Must be specified") if params.nil?
        end
      else
        if name == CODESPACES_HOST_SETUP
          errors.add(
            :host_setup,
            "must be specified"
          )
          return
        end

        if name == CODESPACES_NETWORK_CONFIGURATION
          errors.add(
            :network_configuration,
            "must be specified"
          )
          return
        end

        errors.add(:base, "Must specify exactly one of: enabled_value, maximum_value, minimum_value, allowed_values, params")
      end
    end

    def has_allowed_values?
      CONSTRAINT_CONFIGURATION.dig(name, :type) == TYPE_ALLOWED_VALUES ||
        CONSTRAINT_CONFIGURATION.dig(name, :type) == TYPE_ALLOWED_VALUE
    end

    def no_unexpected_allowed_values
      return true if CONSTRAINT_CONFIGURATION.dig(name, :custom_allowed_values)
      given = allowed_values || []
      expected = self.class.allowable_values_for_policy_owner(name, policy_group&.owner).map(&:name)
      unexpected = given - expected
      if unexpected.any?
        errors.add(:allowed_values, "Invalid values were included: #{unexpected.join(", ")}")
      end
    end

    def validate_maximum_value_is_within_limits_for_idle_timeout
      case
      when maximum_value.nil?
        errors.add(
          :maximum_value,
          "must be a number between #{IDLE_TIMEOUT_MINIMUM_VALUE} and #{IDLE_TIMEOUT_MAXIMUM_VALUE} minutes",
        )
      when T.must(maximum_value) > IDLE_TIMEOUT_MAXIMUM_VALUE
        errors.add(
          :maximum_value,
          "must be less than or equal to #{IDLE_TIMEOUT_MAXIMUM_VALUE} minutes"
        )
      when T.must(maximum_value) < IDLE_TIMEOUT_MINIMUM_VALUE
        errors.add(
          :maximum_value,
          "must be greater than or equal to  #{IDLE_TIMEOUT_MINIMUM_VALUE} minutes"
        )
      end
    end

    def validate_maximum_value_is_within_limits_for_retention_period
      case
      when maximum_value.nil?
        errors.add(
          :maximum_value,
          "must be a number between #{RETENTION_PERIOD_MINIMUM_VALUE} and #{Codespace::MAX_RETENTION_PERIOD} minutes",
        )
      when T.must(maximum_value) > Codespace::MAX_RETENTION_PERIOD
        errors.add(
          :maximum_value,
          "must be less than or equal to #{Codespace::MAX_RETENTION_PERIOD} minutes"
        )
      when T.must(maximum_value) < RETENTION_PERIOD_MINIMUM_VALUE
        errors.add(
          :maximum_value,
          "must be greater than or equal to  #{RETENTION_PERIOD_MINIMUM_VALUE} minutes"
        )
      end
    end

    def validate_host_setup_config
      return if params.nil? # Covered by #one_appropriate_value_type

      repo = Repository.nwo(params["repo"])
      policy_owner = policy_group&.owner # The policy group this constraint belongs to is always created ahead of the constraint in a transaction block

      if (policy_owner.is_a?(Organization) && policy_owner.id != repo&.owner_id) ||
        (policy_owner.is_a?(Business) && policy_owner.id != repo&.owner&.business&.id)
        errors.add(:host_setup, "must specify a repository owned by the policy owner")
      elsif !policy_owner
        errors.add(:policy_group_owner, "must be present")
      end

      if policy_owner.is_a?(Business) && !repo.internal?
        errors.add(:host_setup, "must use a repository with internal visibility")
      end

      current_target_type = policy_group&.policy_group_memberships&.first&.target_type
      return unless current_target_type

      if policy_owner.is_a?(Business)
        if current_target_type == Codespaces::PolicyGroupMembership::TARGET_TYPE_BUSINESS
          biz_records = Codespaces::PolicyGroupMembership.joins(:policy_constraints).
            where(
              target_id: policy_owner,
              policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP }
            ).where.not(policy_group_id: policy_group_id)

          if biz_records.present?
            errors.add(
              :host_setup,
              "can only be added once for 'All organizations' policy target"
            )
          end
        elsif current_target_type == Codespaces::PolicyGroupMembership::TARGET_TYPE_USER
          selected_org_records = Codespaces::PolicyGroupMembership.joins(:policy_constraints, :policy_group).
            where(
              target_id: repo.owner_id,
              policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP },
              policy_group: { owner: policy_owner }
            ).where.not(policy_group_id: policy_group_id)

          if selected_org_records.present?
            errors.add(
              :host_setup,
              "can only be added once per organization"
            )
          end
        end
      else
        if current_target_type == Codespaces::PolicyGroupMembership::TARGET_TYPE_USER
          org_records = Codespaces::PolicyGroupMembership.joins(:policy_constraints).
            where(
              target_id: repo.owner_id,
              policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP }
            ).where.not(policy_group_id: policy_group_id)

          if org_records.present?
            errors.add(
              :host_setup,
              "can only be added once for 'All repositories' policy target"
            )
          end
        elsif current_target_type == Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY
          selected_repo_records = Codespaces::PolicyGroupMembership.joins(:policy_constraints, :policy_group).
            where(
              target_id: policy_group&.policy_group_memberships&.first&.target_id,
              policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP },
              policy_group: { owner: policy_owner }
            ).where.not(policy_group_id: policy_group_id)

          if selected_repo_records.present?
            errors.add(
              :host_setup,
              "can only be added once per repository"
            )
          end
        end
      end
    end

    def validate_network_configuration
      current_target_type = policy_group&.policy_group_memberships&.first&.target_type
      return unless current_target_type && policy_group

      if current_target_type == Codespaces::PolicyGroupMembership::TARGET_TYPE_USER
        owner_id = policy_group&.owner_id
        colliding_org_policy_memberships = Codespaces::PolicyGroupMembership.joins(:policy_constraints).
          where(
            target_id: owner_id,
            policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION }
          ).where.not(policy_group_id: policy_group_id)

        if colliding_org_policy_memberships.present?
          errors.add(
            :network_configuration,
            "can only be added once for 'All repositories' policy target"
          )
        end
      elsif current_target_type == Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY
        selected_repos = policy_group&.policy_group_memberships&.where(target_type: Codespaces::PolicyGroupMembership::TARGET_TYPE_REPOSITORY)&.map(&:target_id)
        colliding_repo_policy_memberships = Codespaces::PolicyGroupMembership.joins(:policy_constraints, :policy_group).
          where(
            target_id: selected_repos,
            policy_constraints: { name:  Codespaces::PolicyConstraint::CODESPACES_NETWORK_CONFIGURATION },
            policy_group: { owner: policy_group&.owner }
          ).where.not(policy_group_id: policy_group_id)

        if colliding_repo_policy_memberships.present?
          errors.add(
            :network_configuration,
            "can only be added once per repository"
          )
        end
      end
    end

    def validate_params
      return if params.nil?
      return validate_network_configuration_selected if name == CODESPACES_NETWORK_CONFIGURATION
      expected = CONSTRAINT_CONFIGURATION.dig(name, :required_keys) || []
      if !expected.all? { |key| params.key?(key) }
        errors.add(:params, "Must specify #{expected.join(", ")}")
      end
    end

    def validate_network_configuration_selected
      expected = CONSTRAINT_CONFIGURATION.dig(name, :required_keys) || []
      if !expected.all? { |key| params.key?(key) }
        errors.add(:network_configuration, "Must select a network configuration")
      end
    end

    def validate_container_image_for_allowed_base_image
      errors.add(:allowed_values, "All values must be a valid container image") if allowed_values.any?(&:empty?)

      # base image is valid if the following conditions are met:
      #   1. It can contain at most 1 '*' character, and if so it must be the final character
      #   2. It can end with ':*' but not with ':' --> in order to allow all tags of the base image
      #   3. It matches the docker image regex
      invalid_values = allowed_values.select { |v| !v.gsub(/(\*|:\*)\z/, "").match(DOCKER_REGEX) || v.chomp("*").include?("*") }
      if invalid_values.any?
        errors.add(:allowed_values, "Invalid values were included: #{invalid_values.join(", ")}")
      end
    end

    def validate_length_allowed_value
      errors.add(:allowed_values, "Must have only one value for this constraint") if allowed_values.length > 1
    end

    def instrument_creation
      GitHub.dogstats.increment("codespaces.policy_constraint.created", tags: ["constraint_name:#{name}"])
    end

    def instrument_destroy
      GitHub.dogstats.increment("codespaces.policy_constraint.destroyed", tags: ["constraint_name:#{name}"])
    end
  end
end
