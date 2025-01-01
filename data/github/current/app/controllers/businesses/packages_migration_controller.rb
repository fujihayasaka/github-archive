# typed: false
# frozen_string_literal: true

class Businesses::PackagesMigrationController < Businesses::BusinessController
  include RegistryTwo::PackagesMigrationHelper
  before_action :business_owner_required, :check_v2_registry_availability

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:reload_package_settings_section]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show_flash_message]

  NAMESPACE_LIMIT_COUNT = 20
  ERROR_NAMESPACE_LIMIT_COUNT = 10

  def get_show_more_index # rubocop:todo GitHub/UseRestfulActions
    session[:show_more_pagination].to_i if session[:show_more_pagination].to_i > 0
  end

  def show
    query = params[:query]
    # this is for redirecting to orgs_list_error_migration when load more is clicked.
    if request.xhr? && !params[:show_more].nil? && params[:show_more] == "true"
      show_error_namespaces(query)
    elsif request.xhr?
      show_searched_namespaces(query)
    else
      # When migration is triggered, in_progress flash message should be visible and on refresh it should disappear.
      session[:show_in_process_flash_message] = false
      if session[:run_migration]
        session[:show_in_process_flash_message] = true
        session[:run_migration] = false
      end
      session[:show_more_pagination] = 1
      render "businesses/settings/packages_migration", locals: {
        query: query,
        error_page_index: get_show_more_index
      }
    end
  end

  # Render the orgs list based on search query
  def show_searched_namespaces(query) # rubocop:todo GitHub/UseRestfulActions
    namespace, unmigrated_package_count = fetch_namespaces(unmigrated_and_inprogress: true, query: query)
    error_namespace, error_package_count = fetch_namespaces(error_only: true, query: query)
    complete_namespace, complete_package_count = fetch_namespaces(migrated_only: true, query: query)

    render partial: "businesses/packages_settings/orgs_list", locals: {
      namespace_count: namespace.count,
      namespaces_list: namespace,
      unmigrated_package_count: unmigrated_package_count,
      error_namespace_count: error_namespace.count,
      error_namespaces_list: error_namespace,
      failed_count: error_package_count,
      complete_namespace_count: complete_namespace.count,
      complete_namespaces_list: complete_namespace,
      completed_count: complete_package_count,
      query: query,
      error_index: get_show_more_index
    }
  end

  def show_error_namespaces(query) # rubocop:todo GitHub/UseRestfulActions
    session[:show_more_pagination] = session[:show_more_pagination] + 1
    namespace, unmigrated_package_count = fetch_namespaces(unmigrated_and_inprogress: true, query: query)
    error_namespace, error_package_count = fetch_namespaces(error_only: true, query: query)
    complete_namespace, complete_package_count = fetch_namespaces(migrated_only: true, query: query)

    render partial: "businesses/packages_settings/orgs_list_error_migration", locals: {
      error_namespace_count: error_namespace.count,
      namespaces:  error_namespace.paginate(page: params[:page], per_page: ERROR_NAMESPACE_LIMIT_COUNT,  total_entries: error_namespace.count, offset: (params[:page].to_i + 1) - 1),
      failed_pkg_count: error_package_count,
      query: query,
      section_header: "failed",
      error_index: get_show_more_index
    }
  end

  # Trigger Namespace migration when 'Start Migration' or 'Re-run Migration' is clicked
  # is_first_run is true when 'Start Migration' is clicked
  # is_first_run is false when 'Re-run Migration' is clicked
  def trigger_namespace_migration # rubocop:todo GitHub/UseRestfulActions
    error_page_index = get_show_more_index
    is_first_run = (params[:is_first_run] == "true")

    if is_first_run
      namespaces, unmigrated_package_count = fetch_namespaces(unmigrated_and_inprogress: true)
    else
      namespaces, unmigrated_package_count = fetch_namespaces(error_only: true)
    end

    GitHub.logger.info(
      "code.function" => __method__,
      "code.namespace" => self.class.name,
    )

    if PackageRegistryHelper.ghes_registry_v2_enabled?
      if Registry::PackagesMigration.find_by_state(:inProgress).nil?
        migrate_namespaces(
          namespaces: namespaces,
          unmigrated_package_count: unmigrated_package_count,
          triggered_by: current_user
        )
        session[:success_message] = true
        session[:run_migration] = true
      end
    else
      render_404 and return
    end

    redirect_to settings_packages_migration_enterprise_path
  end

  # Update the progress bar when the alive channel receives a message
  def update_progress_bar # rubocop:todo GitHub/UseRestfulActions
    render partial: "businesses/packages_settings/section_header", locals: { section_type: "inprogress" }
  end

  # Update the org list when the alive channel receives a message after migration is complete
  def reload_package_settings_section # rubocop:todo GitHub/UseRestfulActions
    redirect_to :back
  end

  # Display the success/failed flash message when the alive channel receives a message after migration is complete
  def show_flash_message # rubocop:todo GitHub/UseRestfulActions
    render partial: "businesses/packages_settings/show_flash_message"
  end

  # Hide the progress message when the alive channel receives a message after migration is complete
  def hide_progress_message_after_migration # rubocop:todo GitHub/UseRestfulActions
    session[:show_in_process_flash_message] = false
    render partial: "businesses/packages_settings/in_progress_flash_message"
  end

  # Hide the progress message when user clickes on close button
  def hide_progress_message_when_closed # rubocop:todo GitHub/UseRestfulActions
    session[:show_in_process_flash_message] = false
    redirect_to settings_packages_migration_enterprise_path
  end

  def hide_success_message # rubocop:todo GitHub/UseRestfulActions
    session[:success_message] = false
    redirect_to settings_packages_migration_enterprise_path
  end

  def check_v2_registry_availability # rubocop:todo GitHub/UseRestfulActions
    render_404 unless GitHub.enterprise? && GitHub.subdomain_isolation? && GitHub.registry_v2_enabled_for_enterprise?
  end
end
