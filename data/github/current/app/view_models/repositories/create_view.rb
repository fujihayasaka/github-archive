# typed: true
# frozen_string_literal: true

module Repositories
  class CreateView
    include UrlHelpers
    include RepositoriesDefaultSelectionHelper
    include Repos::GitHubEnterpriseHelper
    include UrlHelper
    include Repos::OwnerRepoSelectionsPayloadHelper

    # defer loading orgs info for current user until they interact with the
    # control if they're a member of more than ORG_COUNT_DEFER_LIMIT orgs
    ORG_COUNT_DEFER_LIMIT = 50
    DISABLED_BY_POLICY = "(disabled by policy)"

    # Initiate a CreateView object used to control the new repositories page.
    #
    # user - User object.
    # repo - Repository object.
    #
    # Returns the new instance.
    def initialize(user, repo)
      @user = user
      @repo = repo
    end

    attr_reader :user

    # Should the public input be checked?
    #
    # Returns "checked=checked" if so, nil otherwise.
    def public_checked
      if @repo.public?
        "checked=checked"
      end
    end

    # Should the private input be checked?
    #
    # Returns "checked=checked" if so, nil otherwise.
    def private_checked
      if @repo.private?
        "checked=checked"
      end
    end

    # Should the auto init checkbox be checked?
    #
    # Returns "checked=checked" if so, nil otherwise.
    def auto_init_checked
      if @repo.auto_init?
        "checked=checked"
      end
    end

    # Should the given gitignore template choice be selected?
    #
    # template - Template name as String, e.g. "Android".
    #
    # Returns a Boolean.
    def gitignore_checked?(template)
      template == @repo.gitignore_template
    end

    # Name of the selected gitignore template. Defaults to "None".
    #
    # Returns the gitignore template as a String.
    def gitignore_template
      @repo.gitignore_template || "None"
    end

    # Show internal UI if the user is a member of a business that's feature flagged in
    def show_internal_ui?
      @user.businesses.any?
    end

    def show_public_ui?
      @user.public_repositories_available? && GitHub.public_repositories_available?
    end

    def private_visibility_checked?
      return true unless @user.public_repositories_available?
      return true unless GitHub.public_repositories_available?
      return true if @user.businesses.any?
      @repo.private?
    end

    def initially_selected_owner(owner)
      default_owner_initial_selection_for_view(@user, owner)
    end

    # Name of the selected license. Defaults to "None".
    #
    # Returns the gitignore template as a String.
    def license_template
      @repo.license_template || "None"
    end

    # Creates a fun suggested name for users
    def suggested_name
      Repository::SuggestedName.generate
    end

    # @return [Hash{Organization => Hash{Symbol => Symbol}}]
    # The keys of the value hash are :access and :allow_public_repos
    def organizations_info
      @organizations_info ||= user.organizations_info_sorted_hash
    end

    def organizations
      organizations_info.keys
    end

    def user_businesses
      user.businesses
    end

    def installable_marketplace_apps_info
      @marketplace_apps ||= user.installable_marketplace_apps_hash
    end

    def defer_organizations_load?
      user.organizations.size > ORG_COUNT_DEFER_LIMIT
    end

    def custom_user_disabled_message
      return DISABLED_BY_POLICY if show_restrict_create_repositories_in_personal_namespace_message?
      nil
    end

    def supports_profile_readme?(owner)
      GitHub.public_repositories_available? && owner.user?
    end

    def supports_org_profile_readme?(current_user, owner)
      # Enterprise Managed Users cannot create public repositories like .github
      owner.organization? && !owner.enterprise_managed_user_enabled? && GitHub.public_repositories_available?
    end

    def supports_org_member_profile_readme?(current_user, owner)
      owner.organization?
    end

    def organization_info_hash(owner)
      # The hash needs to be the empty object to work with the app/views/repositories/new/_owner.html.erb view,
      # but the org_info_hash helper method returns nil for the React implementation.
      org_info_hash(owner, user) || {}
    end

    def repository_license_field
      "repository[license_template]"
    end

    def repository_gitignore_field
      "repository[gitignore_template]"
    end

    # List of gitignore template options available for init'ing a repository.
    def gitignore_templates
      Gitignore.templates
    end

    def gitignore_menu_items
      [# Default option
        GitHub::Menu::RadioComponent.new(
          text: "None",
          name: repository_gitignore_field,
          value: "",
          replace_text: "None",
          checked: true,
          input_classes: "js-repo-init-setting-menu-option"
        )
      ] + gitignore_templates.map do |gitignore_template|
        GitHub::Menu::RadioComponent.new(
          text: gitignore_template,
          name: repository_gitignore_field,
          value: gitignore_template,
          replace_text: gitignore_template,
          checked: false,
          input_classes: "js-repo-init-setting-menu-option"
        )
      end
    end

    # List of license file options available for init'ing a repository.
    def licenses
      License.sorted_list
    end

    def licenses_menu_items
      [# Default option
        GitHub::Menu::RadioComponent.new(
          text: "None",
          name: repository_license_field,
          value: "",
          replace_text: "None",
          checked: true,
          input_classes: "js-repo-init-setting-menu-option"
        )
      ] + License.sorted_list.map do |license|
        GitHub::Menu::RadioComponent.new(
          text: license.name,
          name: repository_license_field,
          value: license.key,
          replace_text: license.name,
          checked: false,
          input_classes: "js-repo-init-setting-menu-option"
        )
      end
    end

    def show_restrict_create_repositories_in_personal_namespace_message?
      restrict_create_repositories_in_personal_namespace?(user)
    end

    def repo_value(repo_name, experiment_form)
      return CGI.unescape(repo_name) if repo_name
      return @repo.name if experiment_form
      ""
    end

    def owned_organization_ids_for_user(user)
      if GitHub.create_repo_perf?
        user.owned_organization_ids
      else
        nil
      end
    end

    def name_is_restricted?(owner)
      if owner.organization? && owner.feature_flag_enabled?(:member_privilege_rulesets, default: false)
        RulesEngine::RepositoryActionEvaluator.organization_is_protected?(owner, ["repository_name"])
      else
        false
      end
    end
  end
end
