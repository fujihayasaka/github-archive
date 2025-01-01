# typed: true
# frozen_string_literal: true

module Permissions
  # Inherit from this class to define a fine grained resource that conforms to
  # the AbilityCollection interface and is compatible with GitHub Apps
  # permissions.
  #
  # Required:
  # SUBJECT_TYPES                   - Array: strings representing the subject
  #                                   types that belong to this class of resource.
  # ABILITY_TYPE_PREFIX             - String: Used as the subject_type prefix
  #                                   written to the permissions record
  #                                   representing this resource. Also used to
  #                                   generate an attr_reader to access the
  #                                   parent object.
  #
  # Optional:
  # ABILITY_COLLECTION_TYPE         - Class: Either Integration::AbilityCollection
  #                                   or OauthAuthorization::AbilityCollection.
  # ALL_ABILITY_TYPE_PREFIX         - String: Used as the subject_type prefix when
  #                                   the resource is applied to *all*
  #                                   repositories of a given installation target.
  #                                   Should be used in conjunction with
  #                                   INDIVIDUAL_ABILITY_TYPE_PREFIX.
  # INDIVIDUAL_ABILITY_TYPE_PREFIX  - String: Used as the subject type when the
  #                                   resources can apply to individual
  #                                   repositories of an installation target.
  #                                   Should be used in conjunction with
  #                                   ALL_ABILITY_TYPE_PREFIX.
  #
  # READONLY_SUBJECT_TYPES           - Array: strings representing subject types
  #                                    that can only be :read permission.
  #
  # ADMINABLE_SUBJECT_TYPES          - Array: strings representing subject types
  #                                    that can have the permission :admin.
  #
  # CONNECT_ONLY_SUBJECT_TYPES       - Array: strings representing subject types
  #                                    that can only be shown for GitHub Connect
  #                                    integrations.
  #
  # Product Line Configuration:
  # Resources can be restricted to specific product lines (GitHub Enterprise Server,
  # GitHub Enterprise Cloud with/without EMU) through YAML configuration. This is
  # implemented using the following constants and attributes:
  #
  # PUBLIC_SUBJECT_TYPES            - Array: Resources with `visibility: public`
  #                                   available in all product lines unless
  #                                   further restricted by product_lines config.
  #
  # PREVIEW_SUBJECTS_AND_FEATURE_FLAGS - Hash: Resources with `visibility: preview`
  #                                     available only when specific feature flags
  #                                     are enabled. These can be further restricted
  #                                     by product line config.
  #
  # Resources can be controlled in these ways:
  # 1. Base Visibility Controls:
  #    - visibility: public - Available in all environments by default
  #    - visibility: private - Not publicly documented but available
  #    - visibility: preview - Gated behind a feature flag
  #    - visibility: connect_only - Available only for GitHub Connect apps
  #
  # 2. Product Line Restrictions:
  #    - If product_lines is specified, the resource is ONLY available in those product lines
  #    - By default, a resource listed in product_lines is available without additional constraints
  #    - A resource can have product line-specific feature flags
  #
  # 3. Feature Flag Behavior:
  #    - If a product line entry has no feature flag, the resource is always available in that product line
  #    - If a product line entry has a feature flag, the resource is only available when that flag is enabled
  #    - For visibility: preview resources, both the base feature flag AND any product line-specific
  #      feature flags must be enabled
  #
  # Product lines can be restricted in YAML using the product_lines attribute:
  # product_lines:
  #   - ghes                        # Available in GitHub Enterprise Server
  #   - ghec_emu                    # Available in GitHub Enterprise Cloud with EMU
  #   - ghec_non_emu:               # Available in GitHub Enterprise Cloud without EMU
  #       feature_flag: "some_flag" # But only when this flag is enabled
  #
  # E.g.
  #
  # class Repository
  #   class Resources < Permissions::FineGrainedResource
  #     SUBJECT_TYPES = %w(administration contents metadata issues pull_requests)
  #
  #     ABILITY_TYPE_PREFIX = "Repository"
  #     INDIVIDUAL_ABILITY_TYPE_PREFIX = ABILITY_TYPE_PREFIX
  #     ALL_ABILITY_TYPE_PREFIX = "User/repositories"
  #   end
  # end
  #
  # Example usage:
  #
  # Repository::Resources.parent_type
  # => "Repository"
  # Repository::Resources.subject_types
  # => ["administration", "contents", "metadata", "issues", "pull_requests"]
  # Repository::Resources.all_prefixed_subject_types
  # => ["User/repositories/administration", "User/repositories/contents",
  # "User/repositories/metadata", "User/repositories/issues",
  # "User/repositories/pull_requests", "Repository/administration",
  # "Repository/contents", "Repository/metadata", "Repository/issues",
  # "Repository/pull_requests"]
  # Repository::Resources.individual_type_prefixed_subject_types
  # => ["Repository/metadata", "Repository/contents"]
  # repository.resources.issues
  # => #<IntegrationInstallation::AbilityCollection:0x000000012a573340 ...>
  # repository.resources.parent
  # => #<Repository ...>
  # repository.resources.repository
  # => #<Repository ...> # same as parent
  class FineGrainedResource
    def self.parent_type
      const_get("ABILITY_TYPE_PREFIX", false)
    end

    # Public: Return all subject types available for the current environment.
    #
    # This method filters the available subject types based on the current product line
    # (GHES or GitHub.com) without requiring a programmatic_actor.
    # It ensures that tests and other non-actor contexts only see the subject types
    # relevant to their environment, preventing tests from failing due to
    # environment-specific resources being included or excluded incorrectly.
    #
    # Unlike subject_types_for, which requires a programmatic_actor for detailed filtering,
    # this method performs a simplified filtering based only on the current environment.
    #
    # Returns an Array of String subject type names.
    def self.subject_types
      subject_types = []

      # Determine current environment product line
      current_product_line = if GitHub.enterprise?
        :ghes
      else
        :ghec
      end

      # Get base types from SUBJECT_TYPES constant
      base_types = const_get("SUBJECT_TYPES", false)

      # If we have special subject type categories, filter each one
      if const_defined?("PUBLIC_SUBJECT_TYPES", false) ||
        const_defined?("PRIVATE_SUBJECT_TYPES", false) ||
        const_defined?("PREVIEW_SUBJECT_TYPES", false)

        # Process each resource against product line settings
        base_types.each do |subject_type|
          resource_config = GitHub.fine_grained_resource(subject_type)

          # If no config or no product_lines key, the resource is available everywhere
          if !resource_config || !resource_config["product_lines"]
            subject_types << subject_type
            next
          end

          # Otherwise, check if this resource is allowed in the current product line
          allowed = resource_config["product_lines"].any? do |line_entry|
            case line_entry
            when String
              # Match exact or if we're in :ghec, match anything containing "ghec"
              line_entry == current_product_line.to_s ||
                (current_product_line == :ghec && line_entry.to_s.include?("ghec"))
            when Hash
              # If there's a hash with key matching current_product_line or
              # (for :ghec) any key containing "ghec"
              line_entry.keys.any? do |key|
                key == current_product_line.to_s ||
                  (current_product_line == :ghec && key.to_s.include?("ghec"))
              end
            else
              false
            end
          end

          subject_types << subject_type if allowed
        end
      else
        # If no special categories, just use the base types
        subject_types = base_types
      end

      subject_types
    end

    def self.all_prefixed_subject_types(filter = nil)
      if const_defined?("ALL_ABILITY_TYPE_PREFIX", false) && const_defined?("INDIVIDUAL_ABILITY_TYPE_PREFIX", false)
        all_type_prefixed_subject_types(filter) + individual_type_prefixed_subject_types(filter)
      else
        subject_types_with_filter(filter).map { |t| "#{const_get("ABILITY_TYPE_PREFIX", false)}/#{t}" }
      end
    end

    def self.all_type_prefixed_subject_types(filter = nil)
      if const_defined?("ALL_ABILITY_TYPE_PREFIX", false)
        subject_types_with_filter(filter).map { |t| "#{const_get("ALL_ABILITY_TYPE_PREFIX", false)}/#{t}" }
      else
        subject_types_with_filter(filter).map { |t| "#{const_get("ABILITY_TYPE_PREFIX", false)}/#{t}" }
      end
    end

    def self.individual_type_prefixed_subject_types(filter = nil)
      if const_defined?("INDIVIDUAL_ABILITY_TYPE_PREFIX", false)
        subject_types_with_filter(filter).map { |t| "#{const_get("INDIVIDUAL_ABILITY_TYPE_PREFIX", false)}/#{t}" }
      else
        subject_types_with_filter(filter).map { |t| "#{const_get("ABILITY_TYPE_PREFIX", false)}/#{t}" }
      end
    end

    def self.subject_types_for(programmatic_actor)
      subject_types = []
      current_product_line = determine_product_line(programmatic_actor)

      # Include publicly available resources
      if const_defined?("PUBLIC_SUBJECT_TYPES", false)
        # Start with all public subject types and filter by product line restrictions
        public_types = const_get("PUBLIC_SUBJECT_TYPES", false)
        filtered_public_types = filter_by_product_line(public_types, programmatic_actor)
        subject_types.push(*filtered_public_types)
      end

      # Include Connect-specific resources for Connect apps
      if programmatic_actor.is_a?(Integration) && programmatic_actor.connect_app? && const_defined?("CONNECT_ONLY_SUBJECT_TYPES", false)
        subject_types.push(*const_get("CONNECT_ONLY_SUBJECT_TYPES", false))
      end

      # Include feature-flagged preview resources
      if const_defined?("PREVIEW_SUBJECTS_AND_FEATURE_FLAGS", false)
        preview_subjects = const_get("PREVIEW_SUBJECTS_AND_FEATURE_FLAGS", false)
        enabled_preview_resources = []

        # Check each preview resource to see if its feature flag is enabled
        preview_subjects.each do |resource, feature_flag|
          if feature_flag_enabled?(feature_flag, programmatic_actor) && extra_ff_check_passed?(programmatic_actor, resource)
            enabled_preview_resources << resource
          end
        end

        # Only filter by product line if we have preview resources
        if !enabled_preview_resources.empty?
          filtered_preview_types = filter_by_product_line(enabled_preview_resources, programmatic_actor)
          subject_types.push(*filtered_preview_types)
        end
      end

      # Handle excluded subject types
      if const_defined?("EXCLUDED_SUBJECT_TYPES_FOR_TYPE", false) &&
         const_get("EXCLUDED_SUBJECT_TYPES_FOR_TYPE", false).key?(programmatic_actor.class)
        excluded_subject_types = const_get("EXCLUDED_SUBJECT_TYPES_FOR_TYPE")[programmatic_actor.class]
        subject_types -= excluded_subject_types
      end

      subject_types.sort
    end

    # Filter resources by their product line configuration
    #
    # This method checks if resources are allowed for the current product line based on:
    # 1. If a resource has no product_lines key, it's available everywhere
    # 2. If a resource has a product_lines key, checks if the current product line is allowed
    #
    # resources         - Array of resource names to filter
    # programmatic_actor - The actor context used for feature flag checks
    #
    # Returns an Array of filtered resources allowed for the current product line
    def self.filter_by_product_line(resources, programmatic_actor)
      current_product_line = determine_product_line(programmatic_actor)

      resources.select do |resource|
        resource_config = GitHub.fine_grained_resource(resource)
        # If there's no product_lines key or no configuration at all, include the resource
        next true unless resource_config && resource_config["product_lines"]

        allowed_for_product_line?(resource_config, current_product_line, programmatic_actor)
      end
    end

    # Check if a resource is allowed for the current product line
    #
    # resource_config   - Resource configuration hash from YAML
    # current_line      - Symbol or String representing the current product line
    # programmatic_actor - The actor context used for feature flag checks
    #
    # Returns a Boolean indicating if the resource is allowed
    def self.allowed_for_product_line?(resource_config, current_line, programmatic_actor)
      # No product_lines means available everywhere
      return true unless resource_config["product_lines"]

      resource_config["product_lines"].any? do |line_entry|
        case line_entry
        when String
          # Simple string match means the product line is allowed without additional constraints
          line_entry == current_line.to_s
        when Hash
          # Check if the hash has a key matching the current product line
          if line_entry.key?(current_line.to_s)
            config = line_entry[current_line.to_s]

            # No config or empty config means allowed without additional constraints
            next true if config.nil? || config.empty?

            next true unless config["feature_flag"]

            feature_flag_enabled?(config["feature_flag"], programmatic_actor)
          else
            false
          end
        else
          false
        end
      end
    end

    # Check if a feature flag is enabled for the given programmatic actor
    #
    # flag_name         - String name of the feature flag
    # programmatic_actor - The actor context used for feature flag checks
    #
    # Returns a Boolean indicating if the feature flag is enabled
    def self.feature_flag_enabled?(flag_name, programmatic_actor)
      # In GHES environments, always return false
      return false if GitHub.enterprise?

      # Check global flag first (performance optimization)
      return true if FeatureFlag.vexi.enabled?(flag_name, default: false)

      # Check if enabled for the actor or actor's owner
      return true if programmatic_actor.feature_flag_enabled?(flag_name, default: false)
      return true if programmatic_actor.owner.feature_flag_enabled?(flag_name, default: false)

      # For organizations, check associated business
      if programmatic_actor.owner.organization? &&
         programmatic_actor.owner.business&.feature_flag_enabled?(flag_name, default: false)
        return true
      end

      false
    end

    # Determine the current product line based on the programmatic actor
    #
    # This method detects which product line applies to the current context by:
    # 1. Checking if we're in GitHub Enterprise Server (GHES)
    # 2. For GitHub.com, checking if the app is owned by:
    #    - A Business with EMU enabled
    #    - An Organization in an EMU-enabled Business
    #    - A User who is enterprise-managed
    # 3. Otherwise, assuming it's a regular GitHub.com environment without EMU
    #
    # programmatic_actor - The actor context used to determine product line
    #
    # Returns a Symbol representing the product line (:ghes, :ghec_emu, or :ghec_non_emu)
    def self.determine_product_line(programmatic_actor)
      if GitHub.enterprise?
        :ghes
      elsif programmatic_actor.owner.is_a?(Business) && programmatic_actor.owner.enterprise_managed_user_enabled?
        :ghec_emu
      elsif programmatic_actor.owner.organization? && programmatic_actor.owner.business&.enterprise_managed_user_enabled?
        :ghec_emu
      elsif programmatic_actor.owner.user? && programmatic_actor.owner.is_enterprise_managed?
        :ghec_emu
      else
        :ghec_non_emu
      end
    end

    def self.extra_ff_check_passed?(programmatic_actor, resource)
      return true unless const_defined?("EXTRA_FEATURE_FLAG_DEPENDENCIES", false)

      extra_ff_dependencies = const_get("EXTRA_FEATURE_FLAG_DEPENDENCIES", false)

      return true unless extra_ff_dependencies.key?(resource.to_s)

      owner = programmatic_actor.owner

      extra_ff_dependencies[resource.to_s].any? do |_group_name, feature_flags|
        # All flags in this group must be enabled on at least one valid actor
        feature_flags.all? do |flag|
          # Check if flag is enabled on any of the possible actors:
          # - app itself (programmatic_actor)
          # - app's owner (user/organization/business)
          # - business (if owner is an organization with business)
          programmatic_actor.feature_flag_enabled?(flag, default: false) || owner&.feature_flag_enabled?(flag, default: false) || (owner.is_a?(Organization) && owner.business&.feature_flag_enabled?(flag, default: false))
        end
      end
    end

    # Public: Take an Hash of permission/action pairs
    # and filter out the ones that don't belong to
    # the given resource.
    #
    # Example:
    #
    #   Repository::Resources.filter({
    #     "metadata" => :read,
    #     "contents" => :write,
    #     "members" => :read
    #   })
    #
    #   # =>
    #
    #   { "metadata" => :read, "contents" => :read }
    #
    # Returns a Hash.
    def self.filter(permissions)
      permissions.slice(*subject_types)
    end

    # Internal: Filter out the subject_types that are
    # not requested.
    #
    # Example:
    #
    # >> subject_types
    # => ["metadata", "contents" "issues"]
    #
    # >> subject_types_with_filter(["metadata", "contents"])
    # => ["metadata", "contents"]
    #
    # Returns an Array
    def self.subject_types_with_filter(filter)
      return subject_types unless filter.is_a?(Array)
      subject_types & filter
    end

    # Public: Returns readable subject types for this resource.
    #
    # Returns an Array
    def self.readable_subject_types
      subject_types.select { |resource| !Permissions::ResourceRegistry.writeonly_subject_type?(resource) }
    end

    private_class_method :subject_types_with_filter

    attr_reader :parent

    def initialize(parent)
      @parent = parent
    end

    def method_missing(method_name, *args, &block)
      if common_method = common_methods[method_name.to_s]
        common_method.call(*args, &block)
      else
        super
      end
    end

    def respond_to?(method_name, include_all = false)
      common_methods.has_key?(method_name.to_s) || super
    end

    # Intended to be overridden by child classes as they begin enabling Authzd for checking permission
    def authzd_enabled?(action, subject_type)
      false
    end

    def collection_for(resource_name)
      common_methods[resource_name]&.call
    end

    private

    # Internal: A Hash of method names to callables, which implement the common
    # behavior of this class.
    # E.g.
    # {
    #   "repository" => ->(*) { parent },
    #   "contents" => ->(*) { IntegrationInstallation::AbilityCollection.new(...) },
    #   "issues" => ->(*) { IntegrationInstallation::AbilityCollection.new(...) },
    #   etc.
    # }
    def common_methods
      @common_methods ||=
        {}.tap do |m|
          m[self.class.parent_type.underscore] = ->(*_) { parent }
          self.class.subject_types.each do |subject_type|
            m[subject_type] = ability_collection_for(subject_type)
          end
        end
    end

    # Internal: The type of AbilityCollection to use when defining
    # sub-resources. Defaults to IntegrationInstallation::AbilityCollection.
    # Sub-classes may override by defining ABILITY_COLLECTION_TYPE.
    def ability_type_collection
      if self.class.const_defined?(:ABILITY_COLLECTION_TYPE)
        self.class.const_get("ABILITY_COLLECTION_TYPE")
      else
        IntegrationInstallation::AbilityCollection
      end
    end

    # Internal: An abstract collection that refers to the given subject_type.
    # e.g. contents, issues, statuses:
    def ability_collection_for(subject_type)
      ->(*_) {
        ability_type_collection.new(
          parent: parent,
          name: subject_type,
          ability_type_prefix: self.class.const_get("ABILITY_TYPE_PREFIX")
        )
      }
    end
  end
end
