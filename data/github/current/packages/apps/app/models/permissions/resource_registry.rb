# typed: true
# frozen_string_literal: true

# The source of truth for all GitHub Apps related fine-grained *::Resources.
module Permissions
  class ResourceRegistry

    include Singleton

    def self.all
      instance.all
    end

    def self.all_prefixed_subject_types
      instance.all_prefixed_subject_types
    end

    def self.all_type_prefixed_subject_types
      instance.all_type_prefixed_subject_types
    end

    def self.individual_type_prefixed_subject_types
      instance.individual_type_prefixed_subject_types
    end

    def self.preview_subject_type?(subject_type)
      all_preview_subject_types.include?(subject_type)
    end

    def self.preview_subject_type_flags
      instance.preview_subject_type_flags
    end

    def self.all_preview_subject_types
      preview_subject_type_flags.keys
    end

    def self.readonly_subject_type?(resource)
      instance.readonly_subject_types.include?(resource)
    end

    def self.writeonly_subject_type?(resource)
      instance.writeonly_subject_types.include?(resource)
    end

    def self.adminable_subject_type?(resource)
      instance.adminable_subject_types.include?(resource)
    end

    def self.subject_type_enabled_for?(subject_type:, actor: nil, integration: nil)
      return true unless preview_subject_type?(subject_type)

      actors = [actor]
      actors << integration if integration&.persisted?

      if integration&.owner&.organization?
        actors << integration.owner.business
      end

      actors.any? { |checkable| checkable.present? && FeatureFlag.vexi.enabled_or_raise?(preview_subject_type_flags[subject_type], checkable) } # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    def self.parent_of(resource)
      resource_class = all.find do |klass|
        klass.subject_types.include?(resource)
      end

      return unless resource_class

      resource_class.parent_type
    end

    # Public: The permissions currently requested by an App or installation,
    # grouped by resource type.
    #
    # E.g.
    #
    # {
    #   Repository::Resources => { "contents" => :write, "metadata" => :read },
    #   Organization::Resources => { "members" => :read },
    #   User::Resources => { "emails" => :read }
    # }
    #
    # Returns a Hash.
    def self.permissions_by_resource(appish)
      current_permissions =
        case appish
        when Integration then appish.default_permissions
        when IntegrationInstallation then appish.permissions
        when GlobalIntegrationInstallation then appish.integration.default_permissions
        else {}
        end

      result = {}

      current_permissions.each do |perm, action|
        instance.all.select { |k| k.subject_types.include?(perm) }.each do |resource_class|
          next if resource_class == PackageRegistry::Resources
          next if resource_class == ProtectedBranch::Resources
          result[resource_class] = (result[resource_class] || {}).merge({ perm => action })
        end
      end
      result
    end

    def all
      @all ||= [
        Actions::WorkflowRun::Resources,
        Business::Resources,
        Codespace::Resources,
        Organization::Resources,
        Repository::Resources,
        PackageRegistry::Resources,
        ProtectedBranch::Resources,
        PullRequest::Resources,
        User::Resources,
      ]
    end

    def all_prefixed_subject_types
      @all_prefixed_subject_types ||= all.flat_map(&:all_prefixed_subject_types)
    end

    def all_type_prefixed_subject_types
      @all_type_prefixed_subject_types ||= all.flat_map(&:all_type_prefixed_subject_types)
    end

    def individual_type_prefixed_subject_types
      @individual_type_prefixed_subject_types ||= all.flat_map(&:individual_type_prefixed_subject_types)
    end

    def preview_subject_type_flags
      @preview_subject_type_flags ||=
        all.inject({}) do |mem, klass|
          if klass.const_defined?(:PREVIEW_SUBJECTS_AND_FEATURE_FLAGS)
            mem.merge!(klass.const_get("PREVIEW_SUBJECTS_AND_FEATURE_FLAGS"))
          end
          mem
        end
    end

    def readonly_subject_types
      @readonly_subject_types ||=
        all.inject([]) do |mem, klass|
          if klass.const_defined?(:READONLY_SUBJECT_TYPES)
            mem = mem + klass.const_get("READONLY_SUBJECT_TYPES")
          end
          mem
        end
    end

    def writeonly_subject_types
      @writeonly_subject_types ||=
        all.inject([]) do |mem, klass|
          if klass.const_defined?(:WRITEONLY_SUBJECT_TYPES)
            mem = mem + klass.const_get("WRITEONLY_SUBJECT_TYPES")
          end
          mem
        end
    end

    def adminable_subject_types
      @adminable_subject_types ||=
        all.inject([]) do |mem, klass|
          if klass.const_defined?(:ADMINABLE_SUBJECT_TYPES)
            mem = mem + klass.const_get("ADMINABLE_SUBJECT_TYPES")
          end
          mem
        end
    end

  end
end
