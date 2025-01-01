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

    def self.subject_types
      const_get("SUBJECT_TYPES", false)
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

      if const_defined?("PUBLIC_SUBJECT_TYPES", false)
        subject_types.push(*const_get("PUBLIC_SUBJECT_TYPES", false))
      end

      if GitHub.enterprise? && const_defined?("ENTERPRISE_SUBJECT_TYPES")
        subject_types.push(*const_get("ENTERPRISE_SUBJECT_TYPES", false))
      end

      if programmatic_actor.is_a?(Integration) && programmatic_actor.connect_app? && const_defined?("CONNECT_ONLY_SUBJECT_TYPES")
        subject_types.push(*const_get("CONNECT_ONLY_SUBJECT_TYPES", false))
      end

      if const_defined?("PREVIEW_SUBJECTS_AND_FEATURE_FLAGS", false)
        const_get("PREVIEW_SUBJECTS_AND_FEATURE_FLAGS", false).each do |resource, feature_flag|
          app_or_owner_enabled = programmatic_actor.feature_enabled?(feature_flag) || programmatic_actor.owner.feature_enabled?(feature_flag)
          org_business_enabled = programmatic_actor.owner.organization? && programmatic_actor.owner.business&.feature_enabled?(feature_flag)

          if app_or_owner_enabled || org_business_enabled
            subject_types.push(resource)
          end
        end
      end

      if const_defined?("EXCLUDED_SUBJECT_TYPES_FOR_TYPE") && const_get("EXCLUDED_SUBJECT_TYPES_FOR_TYPE").key?(programmatic_actor.class)
        excluded_subject_types = const_get("EXCLUDED_SUBJECT_TYPES_FOR_TYPE")[programmatic_actor.class]
        subject_types -= excluded_subject_types
      end

      subject_types.sort
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
          m[self.class.parent_type.underscore] = ->(*) { parent }
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
      ->(*) {
        ability_type_collection.new(
          parent: parent,
          name: subject_type,
          ability_type_prefix: self.class.const_get("ABILITY_TYPE_PREFIX")
        )
      }
    end
  end
end
