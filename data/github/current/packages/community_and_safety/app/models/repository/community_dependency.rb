# typed: false
# frozen_string_literal: true

# This mixin includes repo-adjacent functionality that is part of the community_and_safety service.
module Repository::CommunityDependency
  # The root code of conduct object for the default branch
  def code_of_conduct
    @code_of_conduct ||= RepositoryCodeOfConduct.new(self)
  end

  # The root contributing guidelines object for the default branch
  def contributing_guidelines
    @contributing ||= RepositoryContributingGuidelines.new(self)
  end

  # Detect under what license the repository is licensed
  #
  # Returns the License model if a license is known, otherwise nil
  def license
    repository_license&.license
  end

  # All of the detected licenses for the repository
  #
  # Returns an empty collection if no licenses are found
  def licenses
    repository_licenses.map(&:license)
  end

  # Detects license files in th repository and stores all results
  # in the repository_licenses table.
  #
  # Returns the license string
  def set_licenses
    RepositoryLicense.set_licenses(self)
  end

  # Detects under what singular license the repository is licensed and stores the result
  # in the repository_licenses table.
  #
  # Returns the license string
  def set_license
    RepositoryLicense.set_license(self)
  end

  # Public: The preferred LICENSE file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_license(tree_name: nil)
    preferred_file(:license, tree_name: tree_name)
  end

  def preferred_citation(tree_name: nil)
    preferred_file(:citation, tree_name: tree_name)
  end

  def async_preferred_license(tree_name: nil)
    async_preferred_file(:license, tree_name: tree_name)
  end

  # Public: The preferred CODE_OF_CONDUCT file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_code_of_conduct
    preferred_file(:code_of_conduct)
  end

  # Public: The preferred CONTRIBUTING file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_contributing
    preferred_file(:contributing)
  end

  def preferred_funding
    preferred_file(:funding)
  end

  def global_preferred_funding
    @global_preferred_funding_memo ||= async_global_preferred_file(:funding).sync
  end

  def async_preferred_funding
    async_preferred_file(:funding)
  end

  # Public: The preferred README file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_readme
    preferred_file(:readme)
  end

  # Public: The __dashboard.md file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_dashboard
    async_preferred_dashboard.sync
  end

  def async_preferred_dashboard
    async_preferred_file(:dashboard)
  end

  def async_preferred_readme(ref_name: nil)
    Promise.all([async_default_branch, async_root]).then do
      branch = ref_name || default_branch
      tree_entry = directory(branch)&.preferred_readme
      next unless tree_entry

      tree_entry.ref_name = branch
      tree_entry
    end
  end

  # Public: The preferred CONTRIBUTING file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_commands
    preferred_file(:commands)
  end

  def async_preferred_commands
    async_preferred_file(:commands)
  end

  # Public: The preferred SUPPORT file from the Repository root.
  #
  # Returns a TreeEntry or nil.
  def preferred_support
    preferred_file(:support)
  end

  # Is code of conduct detection enabled for this repository?
  #
  # Returns true if a public repository or if Enterprise
  def detect_code_of_conduct?
    public?
  end

  # Look through the directory entries of the default branch for a
  # code of conduct file.
  #
  # Returns a boolean.
  def detect_code_of_conduct
    !!preferred_code_of_conduct
  end

  # Look through the directory entries of the default branch for a
  # contributing guidelines file.
  #
  # Returns a boolean.
  def detect_contributing
    !!preferred_contributing
  end

  def disable_interaction_limits
    return unless GitHub.interaction_limits_enabled?
    RepositoryInteractionAbility.disable_active_local_limit_for(self)
  end

  def enqueue_set_license_job
    RepositorySetLicenseJob.perform_later(self)
  end

  # Public: Determine if a given actor can view the community insights for this repository.
  #
  # Returns a Boolean.
  def can_view_community_insights?(actor)
    return false unless actor

    ::Permissions::Enforcer.authorize(
      action: :view_community_insights,
      actor: actor,
      subject: self,
    ).allow?
  end
end
