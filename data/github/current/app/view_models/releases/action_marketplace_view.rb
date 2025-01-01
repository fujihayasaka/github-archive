# typed: true
# frozen_string_literal: true

module Releases
  class ActionMarketplaceView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :action, :current_user, :marketplace_enabled

    def initialize(release:, current_user:, marketplace_enabled:, query_params: {})
      @release = release
      @action = release.repository.action_at_root
      @marketplace_enabled = marketplace_enabled

      @current_user = current_user
      @query_params = query_params
    end

    def potential_marketplace_action?
      GitHub.actions_enabled? && marketplace_enabled && @release.potential_github_action? && metadata_file_values.any?
    end

    def action_package_listed_to_marketplace?
      @action.action_package_listed?
    end

    def metadata_file_values
      # We load in the values from the metadata file to show the user any issues with
      # how they setup their labels.
      @metadata_file_values ||= @action.config_from_metadata_file
    end

    def metadata_file_name
      File.basename(@action.path)
    end

    def metadata_file_is_dockerfile?
      metadata_file_name == "Dockerfile"
    end

    def show_locked?
      return @show_locked unless @show_locked.nil?

      @show_locked = if repository_org_owner.nil?
        potential_marketplace_action? && (user_needs_to_sign_integrator_agreement? || needs_to_setup_two_factor? || spammy?)
      else
        potential_marketplace_action? && (org_needs_to_sign_integrator_agreement? || needs_to_setup_two_factor? || spammy?)
      end
    end

    def show_form?
      return false unless potential_marketplace_action?

      !show_locked?
    end

    def publish_checked_by_default?
      return true if ActiveModel::Type::Boolean.new.cast(@query_params[:marketplace])

      RepositoryActionRelease.where(repository_action: action, published_on_marketplace: true).exists?
    end

    def show_security_contact_field?
      action.owned_by_org?
    end

    def security_contact_default_value
      action.security_email || current_user.email
    end

    def needs_to_setup_two_factor?
      !current_user.two_factor_authentication_enabled?
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def action_primary_category
      @action_primary_category ||= @action&.regular_categories&.first
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def action_secondary_category
      @action_secondary_category ||= @action&.regular_categories&.second
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def regular_categories
      @regular_categories ||= ::Marketplace::Category.where(acts_as_filter: false).order(:name)
    end

    def show_readme_error_message?
      readme_file.nil?
    end

    def metadata_file_name_value
      metadata_file_values[:name]
    end

    def metadata_file_description_value
      metadata_file_values[:description]
    end

    def metadata_file_icon_name_value
      metadata_file_values[:icon_name]
    end

    def metadata_file_color_value
      metadata_file_values[:color]
    end

    def readme_file
      @readme_file ||= action.readme
    end

    def show_metadata_file_error_message?
      !name_valid? || !description_valid?
    end

    def show_metadata_file_warning_message?
      !icon_valid? || !color_valid?
    end

    def show_metadata_file_success_message?
      name_valid? && description_valid? && icon_valid? && color_valid?
    end

    def metadata_file_warning_message
      message = []

      message << "icon" unless icon_valid?
      message << "description" unless description_valid?
      message << "color" unless color_valid?

      connector = message.length == 1 ? "a label for" : "labels for"

      "Improve your Action by adding " + connector + " " + message.to_sentence + "."
    end

    def name_octicon
      return "check" if name_valid?
      "x"
    end

    def description_octicon
      return "check" if description_valid?
      "x"
    end

    def color_octicon
      return "check" if color_valid?
      "alert"
    end

    def icon_octicon
      return "check" if icon_valid?
      "alert"
    end

    def name_valid?
      return false if metadata_file_name_value.nil?

      action.name = metadata_file_name_value
      action.set_slug
      action.validate
      action.errors[:name].empty? && action.errors[:slug].empty?
    end

    def integrator_agreement
      @integrator_agreement ||= Marketplace::Agreement.latest_for_integrators
    end

    def needs_to_sign_integrator_agreement?
      if repository_org_owner.nil?
        user_needs_to_sign_integrator_agreement?
      else
        org_needs_to_sign_integrator_agreement?
      end
    end

    def user_needs_to_sign_integrator_agreement?
      !action.has_signed_integrator_agreement?(user: current_user, agreement: integrator_agreement)
    end

    def org_needs_to_sign_integrator_agreement?
      !action.org_has_signed_integrator_agreement?(agreement: integrator_agreement, org: repository_org_owner)
    end

    def needs_integrator_agreement_copy
      if repository_org_owner
        "#{repository_org_owner.display_login} must"
      else
        "You must"
      end
    end

    def description_valid?
      return false if metadata_file_description_value.nil?

      action.description = metadata_file_description_value
      # Simulate the Action being listed because description validations are more strict
      action.state = "listed"
      action.validate
      action.errors[:description].empty?
    end

    def icon_valid?
      return false if metadata_file_icon_name_value.nil?

      RepositoryActions::Icons::NAMES.include?(metadata_file_icon_name_value.downcase)
    end

    def color_valid?
      return false if metadata_file_color_value.nil?

      RepositoryActions::Colors.select_by_name_or_hex(metadata_file_color_value).present?
    end

    def spammy?
      action.owner&.spammy? || @release.author&.spammy? || current_user&.spammy?
    end

    def repository_org_owner
      return @repository_org_owner if defined?(@repository_org_owner)

      if @release.repository.owner.organization?
        @repository_org_owner = @release.repository.owner
      end
    end
  end
end
