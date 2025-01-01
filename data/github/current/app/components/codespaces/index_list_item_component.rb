# typed: true
# frozen_string_literal: true

class Codespaces::IndexListItemComponent < ApplicationComponent
  include GitHub::Memoizer
  include CodespacesHelper

  STORAGE_UTILIZATION_WAIT_MAX = 10.minutes

  attr_reader :codespace, :usage_allowed, :show_editor_links, :needs_machine_type_change, :needs_base_image_change, :delete_confirmation_message, :sku, :repo_scoped, :is_read_only, :needs_fork_to_push

  def initialize(codespace:, usage_allowed:, show_editor_links:, needs_machine_type_change: false, needs_base_image_change: false, delete_confirmation_message:, repo_scoped: false, is_read_only:, needs_fork_to_push: false, hydro_open_target: "CODESPACES_PAGE")
    @codespace, @usage_allowed, @show_editor_links, @needs_machine_type_change, @needs_base_image_change, @delete_confirmation_message =
      codespace, usage_allowed, show_editor_links, needs_machine_type_change, needs_base_image_change, delete_confirmation_message
    @sku = Codespaces::Skus.sku_by_name(codespace.sku_name)
    @repo_scoped = repo_scoped
    @is_read_only = is_read_only
    @needs_fork_to_push = needs_fork_to_push
    @hydro_open_target = hydro_open_target
  end

  def show_read_only_info_icon?
    is_read_only
  end

  def codespace_status_indicator_color
    if codespace.consuming_compute?
      :default
    else
      :muted
    end
  end

  def show_active_label?
    codespace.consuming_compute?
  end

  def show_failed_label?
    codespace.creation_failed?
  end

  def codespace_url
    codespace_url_from_editor_preferences(codespace: codespace, user: current_user)
  end

  def repository_owner
    codespace.repository.owner
  end

  memoize def click_tracking_attributes
    open_codespace_attributes(codespace: codespace, target: @hydro_open_target)
  end

  memoize def show_storage_utilization?
    !codespace.failed? && storage_utilization_display_text
  end

  memoize def storage_utilization_display_text
    return storage_gb_text if show_storage_for_prebuild?
    return usage_report_link if show_request_usage_report?
    return retrieving_text if retrieving_storage_utilization?

    storage_gb_text
  end

  def storage_gb_text
    return nil unless storage_utilization_in_gb

    "#{storage_utilization_in_gb} GB"
  end

  def retrieving_storage_utilization?
    return true if storage_utilization_in_gb.nil?

    !codespace.environment_data.display_storage_utilization_in_kb && !codespace_is_over_storage_wait_max?
  end

  def show_storage_for_prebuild?
    storage_utilization_in_gb && codespace.environment_data&.attempted_from_prebuild
  end

  def show_request_usage_report?
    return true if codespace.environment_data.nil?

    # The codespace has not completed cache pruning and we've waited 10 minutes
    !codespace.environment_data.display_storage_utilization_in_kb && codespace_is_over_storage_wait_max? ||
      # The codespace does not have a storage_utilization_in_gb value, is a prebuild and we've waited 10 minutes
      !storage_utilization_in_gb && codespace.environment_data.attempted_from_prebuild && codespace_is_over_storage_wait_max?
  end

  def codespace_is_over_storage_wait_max?
    codespace.created_at < STORAGE_UTILIZATION_WAIT_MAX.ago
  end

  def usage_report_link
    # We can't show this in proxima because billing settings are not available to show request usage report
    # We're not sure if proxima users will be able to request usage reports so TBD on that decision for what we should do with storage utilization if we can't get it
    # See: https://github.com/github/codespaces/issues/14635#issuecomment-1654177786

    return "Unavailable" if GitHub.multi_tenant_enterprise?

    content_tag(:a, "Request Usage Report", href: settings_user_billing_path(anchor: "usage", open_metered_usage_report: true), target: "_blank")
  end

  def retrieving_text
    content_tag(:span, "Retrieving…", class: "text-italic")
  end

  memoize def storage_utilization_in_gb
    return nil if codespace.environment_data.nil? || codespace.environment_data.storage_utilization_is_nil?
    return "0.0" if codespace.environment_data.storage_utilization_is_zero?

    utilization = codespace.environment_data.storage_utilization_in_gb.round(2)
    return "#{utilization}" if utilization >= 0.1

    "<0.1"
  end
end
