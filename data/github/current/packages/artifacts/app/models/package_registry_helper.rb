# typed: true
# frozen_string_literal: true

module PackageRegistryHelper

  # Internal: Indicates whether package registry is enabled. Caches return value for 10 sec.
  def self.show_packages?
    return true if GitHub.package_registry_enabled?
    return true if GitHub.actions_packages_enterprise_setup_pending?
    GitHub.registry_enabled_for_enterprise? || GitHub.registry_v2_enabled_for_enterprise?
  end

  # Returns true if this is an enterprise, and the registry feature flag is enabled
  def self.ghes_registry_enabled?
    GitHub.enterprise? && GitHub.registry_enabled_for_enterprise?
  end

  # Returns true if this is an enterprise, and the registry V2 feature flag is enabled
  def self.ghes_registry_v2_enabled?
    GitHub.enterprise? && GitHub.registry_v2_enabled_for_enterprise?
  end

  def self.show_packages_blankslate?
    GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise? && GitHub.actions_packages_enterprise_setup_pending?
  end

  # Returns container registry mode for enterprise
  # supported values are - enabled, disabled and readonly
  def self.container_registry_mode
    return "enabled" unless GitHub.enterprise?    # return enabled for non-enterprise environments
    GitHub.container_registry_mode
  end

  def self.maven_registry_v2_enabled?(user)
    FeatureFlag.vexi.enabled?(:packages_maven_registry_v2, user, default: false)
  end

  def self.registry_v2_ui_enabled?(ecosystem, user)
    case ecosystem
    when "maven"
      maven_registry_v2_enabled?(user)
    else
      false
    end
  end

  # Used for reducing redundency in package naming for migrated packages
  def self.formatted_package_name(package_name, repo_name)
    return package_name if repo_name.blank?

    package_name.gsub("#{repo_name}/", "")
  end

  def self.is_flagged_owner?(owner)
    owner.spammy?
  end

  def self.allow_access_to_actor?(owner, actor)
    return true if !owner.spammy?

    GitHub::Logger.log(
      request_id: GitHub.context[:request_id],
      fn: "PackageRegistryHelper/allow_access_to_actor",
      actor_id: actor&.id,
      owner_id: owner&.id,
      msg: "Request to access spammy namespace content"
    )

    if (owner.organization? || owner.user?) && owner.adminable_by?(actor)
      true
    else
      GitHub::Logger.log(
        request_id: GitHub.context[:request_id],
        fn: "PackageRegistryHelper/allow_access_to_actor",
        msg: "Request to access spammy namespace content denied",
      )
      false
    end
  end

  def self.has_package_with_pending_migration?(deleted_packages)
    deleted_packages.each do |package|
      # adding package type check to not call restrict_delete_restore_on_migration for container type packages
      if %w[docker npm nuget rubygems].include?(package.package_type) && package.restrict_delete_restore_on_migration?
        return true
      end
    end
    false
  end
end
