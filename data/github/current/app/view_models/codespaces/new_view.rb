# typed: true
# frozen_string_literal: true

class Codespaces::NewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :repository, :ref, :pull_request, :sku, :hide_repo_select, :vscs_target_url, :query, :user_settings, :geos, :geo, :region_for_skus, :sku_availability_contexts, :show_prebuild_availability, :show_response_error, :base_image_valid, :template, :region_selection_disabled_message

  attr_initializable :vscs_target, :devcontainer_path, :pickable_devcontainers, :active_devcontainer

  delegate :at_limit?, :codespace_limit, to: :query

  include BranchesHelper
  include CodespacesHelper

  def form_ready?
    repository && (ref || pull_request) && geo
  end

  def codespace
    return unless form_ready?

    attrs = {
      owner: current_user,
      billable_owner: billable_owner,
      devcontainer_path: Codespaces::DevContainer.valid_path_or_nil(devcontainer_path),
      repository_id: repository.id,
    }
    if pull_request
      attrs[:pull_request] = pull_request
    else
      attrs[:ref] = ref&.name
    end
    if template
      attrs[:template_repository_id] = template.repository.id
    end
    Codespace.build(**attrs)
  end

  def vscs_target_config
    if pickable_vscs_target_configs.any? { |config| config&.dig(:name) == @vscs_target&.to_sym }
      Codespaces::Vscs.config_for_target(@vscs_target&.to_sym)
    end
  end

  def vscs_target_config?(target_config)
    vscs_target_config&.dig(:name) == target_config&.dig(:name)
  end

  def vscs_target_display_name
    vscs_target_config&.dig(:display_name) || Codespaces::Vscs.default_target_config&.dig(:display_name)
  end

  def devcontainer_path
    @devcontainer_path.presence || (pickable_devcontainers.first&.path if Codespaces::DevContainer.is_default_path?(pickable_devcontainers.first&.path)) || ""
  end

  def active_devcontainer
    return nil unless devcontainer_path.present?

    @active_devcontainer || pickable_devcontainers.find { |dc| dc.path == devcontainer_path }
  end

  def pickable_devcontainers
    return @pickable_devcontainers if @pickable_devcontainers.present?

    @pickable_devcontainers = Codespaces::DevContainer.list_dev_containers(repository, ref&.target_oid)
  end

  def disambiguate_devcontainer_names_with_paths?
    return @disambiguate_devcontainer_names_with_paths if defined?(@disambiguate_devcontainer_names_with_paths)

    names = @pickable_devcontainers.map { |dc| dc.display_name.downcase }
    @disambiguate_devcontainer_names_with_paths = names.uniq.length != names.length
  end

  def pickable_vscs_target_configs # These are target config objects
    return @pickable_vscs_target_configs if defined?(@pickable_vscs_target_configs)
    @pickable_vscs_target_configs = Codespaces::Vscs.available_vscs_target_configs(current_user)
  end

  def billable_owner
    return nil if repository.nil?

    query.repository_policy.billable_owner
  end

  def usage_allowed?
    return false unless billable_owner

    dev_container = Codespaces::DevContainer.new(repository:, oid: ref&.target_oid, filepath: devcontainer_path, user: current_user)
    Codespaces::AccessChecker.new(billable_owner, user: current_user, repository:).allowed?(
      sku_name: codespace&.sku_name,
      dev_container:,
    )
  end

  def open_directly_in_a_non_web_editor?
    user_settings.prefers_non_web_editor?
  end

  def branch_ref_selector_cache_key
    ref_list_cache_key(repository: repository)
  end

  def creation_disabled_due_to_machine_type?
    return true if sku_availability_contexts.empty?

    sku_availability_contexts.none?(&:enabled)
  end

  def creation_disabled_due_to_base_image?
    !base_image_valid
  end

  def click_tracking_attributes
    create_codespace_attributes(codespace:, target: "ADVANCED_OPTIONS")
  end

  private

  def codespaces_developer_enabled?
    current_user&.feature_enabled?(:codespaces_developer)
  end
end
