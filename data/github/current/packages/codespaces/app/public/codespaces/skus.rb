# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module Skus
    extend GitHub::ResilienceMixin

    # Source: https://github.com/github/codespaces/issues/779
    BASE_HOURLY_RATE = 0.0846

    # Operating Systems
    WINDOWS_OS = "windows"
    LINUX_OS = "linux"

    FEATURE_FLAGS = [
      # "Global" feature flags that gate access for all users and orgs.
      # 32-core and GPU SKUs are being manually enabled for high-powered users:
      LINUX_32CORE_64GB_FEATURE_FLAG = "codespaces_linux_x_large",
      LINUX_6CORE_128GB_NCV3_FEATURE_FLAG = "codespaces_linux_standard_ncv3",
      LINUX_96CORE_64GB_GPU_FEATURE_FLAG = "codespaces_linux_premium_gpu",
      # These three are nonstandard and may wind up being deprecated:
      LINUX_2CORE_64GB_FEATURE_FLAG = "codespaces_linux_2core_64gb",
      LINUX_4CORE_64GB_FEATURE_FLAG = "codespaces_linux_4core_64gb",
      LINUX_8CORE_32GB_FEATURE_FLAG = "codespaces_linux_8core_32gb",
      # Feature flags for deprecated SKUs to clean up. Please don't expand flag audiences:
      LINUX_EXPERIMENTAL_FEATURE_FLAG = "codespaces_linux_experimental",
      LEGACY_LINUX_32CORE_FEATURE_FLAG = "codespaces_linux_premium",

      # This experimental feature flag is used to control the mock skus used for development testing.
      LINUX_DEV_EXPERIMENT_FEATURE_FLAG = "codespaces_linux_dev_experiment",

      # Feature flag for the SKUs (16 core and 32 core) with 256 GB storage
      LINUX_16CORE_256GB_FEATURE_FLAG = "codespaces_linux_16core_256gb",
      LINUX_32CORE_256GB_FEATURE_FLAG = "codespaces_linux_32core_256gb",
    ]

    NO_VALID_MACHINE_TYPES_CATCHALL_MESSAGE = "No valid machine types are available. Machine types may be disallowed by policy set by your organization or enterprise administrator, or by host requirements defined in your dev container configuration."

    class Sku
      class InvalidTierError < StandardError; end

      attr_reader :name, :display_name, :operating_system, :display_description, :storage_in_gb, :storage, :memory, :cpus,
        :display_specs, :display_cpus, :display_specs_without_cores, :display_memory, :display_storage, :global_feature_flag, :gpus,
        :billable

      attr_accessor :prebuild_availability

      def initialize(name:,
                     display_name:,
                     display_description:,
                     operating_system:,
                     global_feature_flag:, # gate access for all users and orgs
                     storage_in_gb:,
                     storage:,
                     memory:,
                     cpus:,
                     gpus:,
                     billable:)
        @name = name
        @display_name = display_name
        @display_description = display_description
        @operating_system = operating_system
        @global_feature_flag = global_feature_flag
        @storage_in_gb = storage_in_gb
        @storage = storage
        @memory = memory
        @cpus = cpus
        @gpus = gpus
        @billable = billable

        @display_cpus = "#{cpus}-core"
        unless @gpus.nil? || @gpus == 0
          @display_cpus += " (#{gpus} GPU)"
        end

        @display_memory = "#{(memory / 1.gigabyte).to_i}GB RAM"
        @display_storage = "#{(storage / 1.gigabyte).to_i}GB storage"

        @display_specs_without_cores = "#{@display_memory} • #{(storage / 1.gigabyte).to_i}GB"
        @display_specs = "#{@display_cpus} • #{@display_specs_without_cores}"
      end

      def allowed_for_user?(user, user_trust_tier = nil)
        # Test accounts are allowed to access any SKU
        return true if GitHub.flipper[:codespaces_automated_testing].enabled?(user)

        # Global feature flags are the highest level SKU gate
        if @global_feature_flag
          # If the feature flag is disabled for the user, then they can't use the SKU
          feature_flag_enabled_for_user = GitHub.flipper[@global_feature_flag].enabled?(user)
          return false if !feature_flag_enabled_for_user

          # If the flag is specifically enabled for the user and not everyone, then they can use the SKU
          feature_flag_globally_enabled = GitHub.flipper[@global_feature_flag].enabled?
          return true if !feature_flag_globally_enabled && feature_flag_enabled_for_user
        end

        # Consider SKU restrictions due to Codespace Dials
        !restricted_by_dial?(user, user_trust_tier)
      end

      def allowed_for_repository?(repository)
        if @global_feature_flag
          feature_flag_enabled_for_repo = GitHub.flipper[@global_feature_flag].enabled?(repository)
          return false unless feature_flag_enabled_for_repo

          # This copies the logic from #allowed_for_user? to ensure that the
          # feature flag is only used if it is _not_ globally enabled.
          feature_flag_globally_enabled = GitHub.flipper[@global_feature_flag].enabled?
          true if !feature_flag_globally_enabled && feature_flag_enabled_for_repo
        end
      end

      def allowed_for_devcontainer?(dev_container)
        return true unless dev_container
        cpus >= dev_container.host_requirements.cpus &&
          gpus >= dev_container.host_requirements.gpus &&
          memory >= dev_container.host_requirements.memory &&
          storage >= dev_container.host_requirements.storage
      rescue Codespaces::DevContainer::ReadError
        # Err on the side of permissive if for whatever reason we can't read the devcontainer.json
        true
      end

      # Indicates the org or business can use this SKU in machine type allowlists for Codespaces policies.
      sig { params(owner: T.any(Business, Organization)).returns(T::Boolean) }
      def allowable_by_policy_owner?(owner)
        return true unless @global_feature_flag
        owner.feature_enabled?(@global_feature_flag.to_sym)
      end

      def gpu?
        gpus.present? && gpus > 0
      end

      def prebuild_available?
        prebuild_availability.present? && prebuild_availability == Prebuilds::AvailabilityStatus::READY
      end

      def prebuild_in_progress?
        prebuild_availability.present? && (prebuild_availability == Prebuilds::AvailabilityStatus::IN_PROGRESS)
      end

      def restricted_by_dial?(actor, actor_trust_tier)
        if actor.user?
          restricted_by_user_dial?(actor, actor_trust_tier)
        elsif actor.organization?
          restricted_by_org_dial?(actor, actor_trust_tier)
        end
      end

      def unbillable?
        !billable
      end

      private

      def restricted_by_user_dial?(user, user_trust_tier)
        user_trust_tier ||= Codespaces::Tier.for_user(user)

        tier_value = user_trust_tier.tier

        dial_map = {
          TrustTiers::Tier::UNTRUSTED => Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedUser.new,
          TrustTiers::Tier::NEUTRAL => Codespaces::Dials::MaximumCoreCountPerCodespaceForNeutralUser.new,
          TrustTiers::Tier::TRUSTED => nil,
        }
        raise InvalidTierError, "Invalid user trust tier" unless dial_map.key?(tier_value)
        cpu_dial = dial_map[tier_value]

        return false unless cpu_dial

        cpus > cpu_dial.value.to_i
      end

      def restricted_by_org_dial?(org, org_trust_tier)
        org_trust_tier ||= Codespaces::Tier.for_billable_owner(org)

        tier_value = org_trust_tier.tier

        dial_map = {
          TrustTiers::Tier::UNTRUSTED => Codespaces::Dials::MaximumCoreCountPerCodespaceForUntrustedOrg.new,
          TrustTiers::Tier::NEUTRAL => Codespaces::Dials::MaximumCoreCountPerCodespaceForNeutralOrg.new,
          TrustTiers::Tier::TRUSTED => nil,
        }

        raise InvalidTierError, "Invalid org trust tier" unless dial_map.key?(tier_value)
        cpu_dial = dial_map[tier_value]

        return false unless cpu_dial

        cpus > cpu_dial.value.to_i
      end
    end

    class << self
      private

      def get_devcontainer(repository:, ref: nil, devcontainer_path: nil)
        ref ||= repository.default_branch

        with_database_error_fallback do
          ref_for_oid = Codespaces::GetTargetRef.call(repository: repository, name_or_oid: ref)
          if target_oid = ref_for_oid&.target_oid
            dev_container = Codespaces::DevContainer.new(repository: repository, oid: target_oid, filepath: devcontainer_path)
          end
        end
      end

      def add_repo_specific_attributes_for_serialization(skus, repository, location: nil, devcontainer_path: nil, fetch_prebuild_availability:, codespace_owner:, **args)
        add_prebuild_availability(skus, repository, codespace_owner, location: location, devcontainer_path: devcontainer_path, **args) if fetch_prebuild_availability
      end

      def add_prebuild_availability(skus, repository, codespace_owner, location: nil, devcontainer_path: nil, **args)
        # Always reset prebuild_availability to nil if we cannot fetch the info
        # because these skus persist in memory on the module.
        # This is unfortunate but we should refactor skus at some point.
        # Issue here: https://github.com/github/codespaces/issues/4724
        unless repository && location
          return skus.each { |sku| sku.prebuild_availability = nil }
        end

        prebuild_availability = begin
          Codespaces::FetchPrebuildModeAvailability.call(repository: repository, location: location, devcontainer_path: devcontainer_path, codespace_owner: codespace_owner, **args) # needs more specific args like ref and oid if present
        rescue ActiveModel::ValidationError => e
          nil
        end
        include_prebuild_availability = Codespaces::Prebuilds.configured?(repository) && prebuild_availability.present?

        # add prebuild availability to the skus
        skus.each do |sku|
          sku.prebuild_availability = begin
            if include_prebuild_availability
              prebuild_availability.fetch(sku.name, Prebuilds::AvailabilityStatus::NONE)
            else
              nil
            end
          end
        end
      end
    end

    MACHINE_INFO = {
      # 32 GB Linux SKUs
      basicLinux32gb: {
        display_name: "2 cores, 8 GB RAM, 32 GB storage",
        display_description: "2CPU X 8GB (32 GB)",
        operating_system: LINUX_OS,
        storage_in_gb: 32,
        storage: 32.gigabytes,
        memory: 8.gigabytes,
        cpus: 2,
        billable: true,
      },
      standardLinux32gb: {
        display_name: "4 cores, 16 GB RAM, 32 GB storage",
        display_description: "4CPU X 16GB (32 GB)",
        operating_system: LINUX_OS,
        storage_in_gb: 32,
        storage: 32.gigabytes,
        memory: 16.gigabytes,
        cpus: 4,
        billable: true,
      },
      premiumLinux32gb: {
        display_name: "8 cores, 32 GB RAM, 32 GB storage",
        display_description: "8CPU X 32GB (32 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_8CORE_32GB_FEATURE_FLAG,
        storage_in_gb: 32,
        storage: 32.gigabytes,
        memory: 32.gigabytes,
        cpus: 8,
        billable: true,
      },
      # 64 GB Linux SKUs
      basicLinux: {
        display_name: "2 cores, 8 GB RAM, 64 GB storage",
        display_description: "2CPU X 8GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_2CORE_64GB_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 8.gigabytes,
        cpus: 2,
        billable: true,
      },
      standardLinux: {
        display_name: "4 cores, 16 GB RAM, 64 GB storage",
        display_description: "4CPU X 16GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_4CORE_64GB_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 16.gigabytes,
        cpus: 4,
        billable: true,
      },
      premiumLinux: {
        display_name: "8 cores, 32 GB RAM, 64 GB storage",
        display_description: "8CPU X 32GB (64 GB)",
        operating_system: LINUX_OS,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 32.gigabytes,
        cpus: 8,
        billable: true,
      },
      standardLinuxAMD: {
        display_name: "4 cores (AMD), 16 GB RAM, 32 GB storage",
        display_description: "4CPU X 16GB (32 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_EXPERIMENTAL_FEATURE_FLAG,
        storage_in_gb: 32,
        storage: 32.gigabytes,
        memory: 16.gigabytes,
        cpus: 4,
      },
      prototypePremiumLinux: {
        display_name: "8 Cores (effective), 16 GB RAM (effective), 32 GB storage",
        display_description: "8CPU X 16GB (32 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_EXPERIMENTAL_FEATURE_FLAG,
        storage_in_gb: 32,
        storage: 32.gigabytes,
        memory: 16.gigabytes,
        cpus: 8,
      },
      extremeLinux: { # Deprecated https://github.com/github/codespaces/issues/7241
        display_name: "32 cores, 64 GB RAM, 64 GB storage",
        display_description: "32CPU X 64GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LEGACY_LINUX_32CORE_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 64.gigabytes,
        cpus: 32,
        billable: true,
      },
      largePremiumLinux: {
        display_name: "16 cores, 64 GB RAM, 128 GB storage",
        display_description: "16CPU X 64GB (128 GB)",
        operating_system: LINUX_OS,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 64.gigabytes,
        cpus: 16,
        billable: true,
      },
      standardLinuxNcv3: {
        display_name: "6 cores (1 GPU), 112 GB RAM, 128 GB storage",
        display_description: "6CPU X 112GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_6CORE_128GB_NCV3_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 112.gigabytes,
        cpus: 6,
        gpus: 1,
      },
      premiumLinuxGPU: {
        display_name: "96 cores (8 GPU), 900 GB RAM, 64 GB storage",
        display_description: "96CPU X 900GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_96CORE_64GB_GPU_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 900.gigabytes,
        cpus: 96,
        gpus: 8,
      },
      # 128 GB Linux SKUs
      xLargePremiumLinux: {
        display_name: "32 cores, 128 GB RAM, 128 GB storage",
        display_description: "32CPU X 128GB (128 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_32CORE_64GB_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 128.gigabytes,
        cpus: 32,
        billable: true,
      },
       # 256 GB Linux SKUs
       largePremiumLinux256gb: {
        display_name: "16 cores, 64 GB RAM, 256 GB storage",
        display_description: "16CPU X 64GB (256 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_16CORE_256GB_FEATURE_FLAG,
        storage_in_gb: 256,
        storage: 256.gigabytes,
        memory: 64.gigabytes,
        cpus: 16,
        billable: true,
      },
       xLargePremiumLinux256gb: {
        display_name: "32 cores, 128 GB RAM, 256 GB storage",
        display_description: "32CPU X 128GB (256 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_32CORE_256GB_FEATURE_FLAG,
        storage_in_gb: 256,
        storage: 256.gigabytes,
        memory: 128.gigabytes,
        cpus: 32,
        billable: true,
      },
      # Experimental SKUs for development testing
      ExperimentalLinux1: {
        display_name: "ExperimentalLinux1 2 cores, 4 GB RAM, 64 GB storage",
        display_description: "2CPU X 4GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 4.gigabytes,
        cpus: 2,
      },
      ExperimentalLinux2: {
        display_name: "ExperimentalLinux2 2 cores, 4 GB RAM, 64 GB storage",
        display_description: "2CPU X 4GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 4.gigabytes,
        cpus: 2,
      },
      ExperimentalLinux3: {
        display_name: "ExperimentalLinux3 2 cores, 4 GB RAM, 64 GB storage",
        display_description: "2CPU X 4GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 4.gigabytes,
        cpus: 2,
      },
      ExperimentalLinux4: {
        display_name: "ExperimentalLinux4 4 cores, 8 GB RAM, 64 GB storage",
        display_description: "4CPU X 8GB (64 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 64,
        storage: 64.gigabytes,
        memory: 8.gigabytes,
        cpus: 4,
      },
      ExperimentalLinux5: {
        display_name: "ExperimentalLinux5 8 cores, 16 GB RAM, 128 GB storage",
        display_description: "8CPU X 16GB (128 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 16.gigabytes,
        cpus: 8,
      },
      ExperimentalLinux6: {
        display_name: "ExperimentalLinux6 16 cores, 32 GB RAM, 128 GB storage",
        display_description: "16CPU X 32GB (128 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 32.gigabytes,
        cpus: 16,
      },
      ExperimentalLinux7: {
        display_name: "ExperimentalLinux7 32 cores, 64 GB RAM, 128 GB storage",
        display_description: "32CPU X 64GB (128 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 64.gigabytes,
        cpus: 32,
      },
      ExperimentalLinux8: {
        display_name: "ExperimentalLinux8 8 cores, 32 GB RAM, 128 GB storage",
        display_description: "8CPU X 32GB (128 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 32.gigabytes,
        cpus: 8,
      },
      ExperimentalLinux9: {
        display_name: "ExperimentalLinux9 16 cores, 64 GB RAM, 128 GB storage",
        display_description: "16CPU X 64GB (128 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 64.gigabytes,
        cpus: 16,
      },
      ExperimentalLinux10: {
        display_name: "ExperimentalLinux10 32 cores, 128 GB RAM, 128 GB storage",
        display_description: "32CPU X 128GB (128 GB)",
        operating_system: LINUX_OS,
        global_feature_flag: LINUX_DEV_EXPERIMENT_FEATURE_FLAG,
        storage_in_gb: 128,
        storage: 128.gigabytes,
        memory: 128.gigabytes,
        cpus: 32,
      },
    }

    # Sets hash where keys are sku names, values are instances of Codespaces::Skus::Sku
    # Example: { basicLinux: Sku.new(name: :basicLinux, ...), ...etc }
    SKUS = begin
      Codespace.sku_names.keys.map(&:to_sym).reduce({}) do |skus, sku_name|
        machine_info = MACHINE_INFO.fetch(sku_name)
        skus[sku_name] = Sku.new(
          name: sku_name,
          display_name: machine_info.fetch(:display_name),
          operating_system: machine_info.fetch(:operating_system),
          global_feature_flag: machine_info.fetch(:global_feature_flag, nil),
          display_description: machine_info.fetch(:display_description, nil),
          storage_in_gb: machine_info.fetch(:storage_in_gb, nil),
          storage: machine_info.fetch(:storage, nil),
          memory: machine_info.fetch(:memory, nil),
          cpus: machine_info.fetch(:cpus, nil),
          gpus: machine_info.fetch(:gpus, 0),
          billable: machine_info.fetch(:billable, false),
        )
        skus
      end
    end

    def self.valid_sku_names
      Codespace.sku_names.keys
    end

    def self.valid_sku_cpus
      SKUS.values.map(&:cpus).sort.uniq
    end

    def self.allowed_for_user(user)
      user_trust_tier = Codespaces::Tier.for_user(user)
      SKUS.values.select { |sku| sku.allowed_for_user?(user, user_trust_tier) }
    end

    def self.allowed_for_repository(repository)
      SKUS.values.select { |sku| sku.allowed_for_repository?(repository) }
    end

    def self.allowed(owner, billable_owner, repository)
      skus = allowed_for_user(owner)
      skus = skus.union(allowed_for_user(billable_owner)) if billable_owner && owner != billable_owner
      skus = skus.union(allowed_for_repository(repository)) unless repository.public?
      skus
    end

    def self.allowed_for_new_codespace(owner:, billable_owner:, vscs_target:, location:, repository:, ref: nil, dev_container: nil, devcontainer_path: nil, vscs_target_url: nil, filter_by_policy: true)
      gh_allowed_skus = allowed(owner, billable_owner, repository)
      vscs_allowed_sku_names = Cache.get(vscs_target || Codespaces::Vscs.default_target, location, vscs_target_url, skip_location_validation: owner.feature_enabled?(:codespaces_developer)).map { |sku| sku[:name] }
      skus = gh_allowed_skus.select { |sku| sku.name.in?(vscs_allowed_sku_names) }

      skus = Codespaces::MachinePolicy.filter_skus_by_machine_policy(skus: skus, repository: repository, billable_owner: billable_owner) if filter_by_policy
      dev_container ||= get_devcontainer(repository:, ref:, devcontainer_path:)
      filter_by_dev_container(skus, dev_container)
    end

    def self.allowed_for_existing_codespace(codespace, dev_container: nil, filter_by_policy: true, vscs_target_url: nil)
      raise ArgumentError, "codespace must be persisted" unless codespace.persisted?
      sku_for_requirements = sku_by_name(codespace.sku_name)
      return [] unless sku_for_requirements

      owner = codespace.owner
      billable_owner = codespace.billable_owner

      gh_allowed_skus = allowed(owner, billable_owner, codespace.repository)

      vscs_allowed_skus = Cache.get(codespace.vscs_target, codespace.location, vscs_target_url, skip_location_validation: owner.feature_enabled?(:codespaces_developer))
      current_valid_sku = vscs_allowed_skus.find { |sku| sku[:name] == sku_for_requirements.name }

      return [] unless current_valid_sku
      skus = gh_allowed_skus.select { |sku| sku.name.in?(current_valid_sku[:transitions]) || sku.name == current_valid_sku[:name] }

      if filter_by_policy
        skus = Codespaces::MachinePolicy.filter_skus_by_machine_policy(skus: skus, repository: codespace.repository, billable_owner: billable_owner)
      end
      filter_by_dev_container(skus, dev_container)
    end

    def self.allowed_for_display(codespace: nil, owner: nil, billable_owner: nil, repository: nil, location: nil, vscs_target: nil, vscs_target_url: nil, dev_container: nil, ref: nil, filter_by_policy: true, fetch_prebuild_availability: true)
      dd_tags = [
        "request_prebuild_mode:#{Codespaces::Prebuilds.configured?(repository)}",
        "existing_codespace:#{codespace.present?}"
      ]
      name = "codespaces.skus.allowed_for_display"

      GitHub.dogstats.distribution_time("#{name}.latency", tags: dd_tags) do
        skus = if codespace
          skus = allowed_for_existing_codespace(codespace, dev_container: dev_container, filter_by_policy: filter_by_policy, vscs_target_url: vscs_target_url)
          if codespace.sku_name
            current_sku = sku_by_name(codespace.sku_name)
            unless current_sku.in?(skus) # Always display the current SKU
              skus << current_sku
            end
          end
          skus
        else
          raise ArgumentError, "owner must be provided if codespace is not provided" if owner.nil?
          raise ArgumentError, "billable_owner must be provided if codespace is not provided" if owner.nil?
          raise ArgumentError, "repository must be provided if codespace is not provided" if owner.nil?
          allowed_for_new_codespace(
            owner: owner,
            billable_owner: billable_owner,
            repository: repository,
            vscs_target: vscs_target,
            vscs_target_url: vscs_target_url,
            location: location,
            ref: ref,
            dev_container: dev_container,
            filter_by_policy: filter_by_policy,
          )
        end

        return skus if skus.empty?

        self.add_repo_specific_attributes_for_serialization(
          skus,
          repository || codespace&.repository,
          ref_name: ref || codespace&.ref,
          location: location || codespace&.location,
          vscs_target: vscs_target || codespace&.vscs_target,
          devcontainer_path: dev_container&.filepath || codespace&.devcontainer_path,
          fetch_prebuild_availability: fetch_prebuild_availability,
          codespace_owner: codespace&.owner,
        )

        resource_ascending_skus(skus)
      end
    end

    def self.valid_sku_for_existing_codespace?(sku_name, codespace)
      allowed_for_existing_codespace(codespace).any? { |sku| sku.name.to_s == sku_name.to_s }
    end

    def self.resource_ascending_skus(skus)
      skus.sort do |sku1, sku2|
        [sku1.gpus, sku1.cpus, sku1.memory, sku1.storage] <=> [sku2.gpus, sku2.cpus, sku2.memory, sku2.storage]
      end
    end

    def self.sku_availability_contexts_for_display(repository_policy, codespace: nil, location: nil, vscs_target: nil, vscs_target_url: nil, dev_container: nil, ref: nil, preferred_default: nil, fetch_prebuild_availability: true)
      skus = if repository_policy.present? && !repository_policy.can_attempt_create?
        []
      else
        # Don't filter SKUs by dev_container or policy in this call, so that we can do it in the AvailabilityContext class and capture explanations.
        allowed_for_display(
          owner: repository_policy.user,
          billable_owner: repository_policy.billable_owner,
          repository: repository_policy.repository,
          codespace: codespace,
          location: location,
          vscs_target: vscs_target,
          vscs_target_url: vscs_target_url,
          filter_by_policy: false,
          ref: ref,
          fetch_prebuild_availability: fetch_prebuild_availability,
        )
      end
      policy_allowed_skus = nil
      if repository_policy.present?
        policy_allowed_skus = Codespaces::MachinePolicy.filter_skus_by_machine_policy(skus: skus, repository: repository_policy.repository, billable_owner: repository_policy.billable_owner)
      end
      AvailabilityContext.for_skus(skus, dev_container: dev_container, policy_allowed_skus: policy_allowed_skus, preferred_default: preferred_default)
    end

    def self.sku_by_name(name)
      SKUS.fetch(name&.to_sym, nil)
    end

    # Returns the default SKU for a given repository, owner, and location. A different ref and billable_owner
    # may be supplied. If a billable_owner is supplied its allowed SKUs will be unioned with the owner's. The
    # ref is only required so we can determine the appropriate devcontainer.
    def self.default_sku(repository:,
                         owner:,
                         location:,
                         ref: repository.default_branch,
                         billable_owner: owner,
                         vscs_target: Codespaces::Vscs.default_target,
                         devcontainer_path: nil)

      allowed_skus = allowed_for_new_codespace(
        owner: owner,
        billable_owner: billable_owner,
        vscs_target: vscs_target,
        location: location,
        repository: repository,
        ref: ref,
        devcontainer_path: devcontainer_path,
      )

      # Grab the first allowed sku in resource-ascending order as the default SKU.
      resource_ascending_skus(allowed_skus).first
    end

    def self.filter_by_dev_container(skus, dev_container)
      return skus if dev_container.nil?

      skus.select { |sku| sku.allowed_for_devcontainer?(dev_container) }
    end
  end
end
