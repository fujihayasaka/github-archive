# typed: true
# frozen_string_literal: true

module PackageSettings

  class ListActionPackageOnMarketplaceComponent < ApplicationComponent
    include RepositoryActionHelper

    def render?
      return false if !GitHub.marketplace_enabled?
      return false if !GitHub.flipper[:action_package_marketplace].enabled?(current_user)
      true
    end

    def initialize(action:)
      @action = action
    end

    attr_reader :action

    memoize def action_package_listed
      repository_action = RepositoryAction.listed.find_by(repository: action.repository)
      if repository_action.present?
        repository_action.action_package_listed?
      end
    end

    memoize def integrator_agreement
      @integrator_agreement ||= Marketplace::Agreement.latest_for_integrators
    end

    memoize def user_needs_to_sign_integrator_agreement?
      !action.has_signed_integrator_agreement?(user: current_user, agreement: integrator_agreement)
    end

    memoize def org_needs_to_sign_integrator_agreement?
      !action.org_has_signed_integrator_agreement?(agreement: integrator_agreement, org: repository_org_owner)
    end

    memoize def needs_to_sign_integrator_agreement?
      if repository_org_owner.nil?
        user_needs_to_sign_integrator_agreement?
      else
        org_needs_to_sign_integrator_agreement?
      end
    end

    memoize def repository_org_owner

      if action.repository.owner.organization?
        @repository_org_owner = action.repository.owner
      end
    end

    memoize def readme_file
      @readme_file ||= action.readme
    end

    memoize def metadata_file_name
      File.basename(@action.path)
    end

    memoize def metadata_file_values
      # We load in the values from the metadata file to show the user any issues with
      # how they setup their labels.
      @metadata_file_values ||= action.config_from_metadata_file
    end

    memoize def metadata_file_name_value
      metadata_file_values[:name]
    end

    memoize def toggle_list_action_path
      toggle_list_action_package_path(action.repository.owner.organization? ? "orgs" : "users", action.repository.owner.display_login, "container", action.repository.name)
    end

    memoize def name_valid?
      return false if metadata_file_name_value.nil?

      action.name = metadata_file_name_value
      action.set_slug
      action.validate
      action.errors[:name].empty? && action.errors[:slug].empty?
    end

    def metadata_file_description_value
      metadata_file_values[:description]
    end

    def description_valid?
      return false if metadata_file_description_value.nil?

      action.description = metadata_file_description_value
      # Simulate the Action being listed because description validations are more strict
      action.state = "listed"
      action.validate
      action.errors[:description].empty?
    end

    memoize def action_requirements_met?
      total_requirements = 3
      requirements_met = total_requirements

      if readme_file.nil?
        requirements_met -= 1
      end

      if name_valid? == false
        requirements_met -= 1
      end

      if description_valid? == false
        requirements_met -= 1
      end

      [requirements_met, total_requirements]
    end

    def csrf_token
      authenticity_token_for(toggle_list_action_path)
    end
  end
end
