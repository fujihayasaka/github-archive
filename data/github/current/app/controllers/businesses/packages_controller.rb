# typed: true
# frozen_string_literal: true

class Businesses::PackagesController < Businesses::BusinessController
  before_action :business_owner_required, :check_packages_availability

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  def show
    respond_to do |format|
      format.html do
        if request.xhr?
          package_type, page = params["package_type"], params["page"]
          logins = Registry::Package.page_logins_by_package_type(package_type, page)
          headers["Cache-Control"] = "no-cache, no-store"

          render partial: "businesses/settings/orgs", locals: {
              package_type: package_type,
              logins: logins
          }
        else
          @packages_settings = Configurable::PackageAvailability.package_availability

          packages_by_type = Hash.new
          logins = Hash.new
          types_with_published_packages = []
          total_published_packages = 0

          Registry::Package.supported_package_type_values.each do |type|
            packages_by_type[type] = Registry::Package.package_data_for_type(type)
            logins[type] = Registry::Package.page_logins_by_package_type(type, 1)
            if packages_by_type[type].total_pkgs_published_count > 0
              types_with_published_packages.push(packages_by_type[type].pretty_name)
              total_published_packages += packages_by_type[type].total_pkgs_published_count
            end
          end

          render "businesses/settings/packages", locals: {
              packages_by_type: packages_by_type,
              logins: logins,
              types_with_published_packages: types_with_published_packages,
              total_published_packages: total_published_packages
          }
        end
      end
    end
  end

  def update_packages_settings # rubocop:todo GitHub/UseRestfulActions
    @global_packages_availability = Configurable::PackageAvailability.package_availability
    global_state = params["package_availability"]

    validate_setting value: global_state, valid_values: Configurable::PackageAvailability::PACKAGE_AVAILABILITY_VALUES

    # 1. set global state
    this_business.set_package_availability(global_state, actor: current_user)

    # 2. update settings per package type if managed
    if global_state == Configurable::PackageAvailability::MANAGED && params["package_types_enabled"].present?
      Registry::Package::PUBLICLY_SUPPORTED_TYPES.each do |type|
        type_name = type.to_s

        if params["package_types_enabled"][type_name] == "default"
          next
        elsif params["package_types_enabled"][type_name].blank?
          params["package_types_enabled"][type_name] = "off"
        end

        enabled = (params["package_types_enabled"][type_name] == "on")

        this_business.set_package_type_availability(type, enabled, actor: current_user)
      end
    end

    redirect_to :back
  end

  def check_packages_availability # rubocop:todo GitHub/UseRestfulActions
    render_404 unless GitHub.enterprise? && GitHub.registry_enabled_for_enterprise?
  end
end
