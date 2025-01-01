# typed: true
# frozen_string_literal: true

class Businesses::Settings::PackagesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include ActionView::Helpers::TextHelper

  attr_reader :business, :is_managed, :is_disabled
  attr_accessor :current_selected, :pkgs_by_type, :package_availabilities, :total_published_packages, :types_with_published_packages, :paged_logins

  def initialize(**args)
    super(args)

    @business = args[:business]
    @is_managed = Configurable::PackageAvailability::MANAGED
    @is_disabled = Configurable::PackageAvailability::DISABLED
    @current_selected = Configurable::PackageAvailability.package_availability

    @package_availabilities = {}
    Registry::Package::PUBLICLY_SUPPORTED_TYPES.each do |type|
      @package_availabilities[type.to_s] = @business.managed_package_type_enabled?(type.to_s)
    end
  end

  def select_list
    @select_list ||= [
      {
        heading: "Enabled",
        description: "GitHub Packages available to everyone.",
        value: Configurable::PackageAvailability::ENABLED,
        selected: @current_selected == Configurable::PackageAvailability::ENABLED
      },
      {
        heading: "Managed",
        description: "Configure settings per package type.",
        value: Configurable::PackageAvailability::MANAGED,
        selected: @current_selected == Configurable::PackageAvailability::MANAGED
      },
      {
        heading: "Disabled",
        description: "GitHub Packages is fully disabled",
        value: Configurable::PackageAvailability::DISABLED,
        selected: @current_selected == Configurable::PackageAvailability::DISABLED
      }
    ]
  end

  def button_text
    selected_option[:heading]
  end

  def input_value
    selected_option[:value]
  end

  def selected_option
    select_list.find { |s| s[:selected] }
  end

  def form_path
    urls.update_settings_packages_enterprise_path(business.slug)
  end

  def package_type_count_description(published_pkgs_count)
    return "No packages published" if published_pkgs_count == 0
    package_data_description = "#{pluralize(published_pkgs_count, "package")} published by"
  end

  def package_type_orgs_description(distinct_owners_count, distinct_owners_to_enumerate)
    messages = distinct_owners_to_enumerate.map { |owner| owner[:login] }
    diff = distinct_owners_count - distinct_owners_to_enumerate.length
    if diff > 0
      messages.push("#{pluralize(diff, "more organization")}")
    end

    messages.to_sentence
  end

  def managed_warning_message(types_with_published_packages, total_published_packages)
    types = types_with_published_packages.to_sentence
    is_plural = (total_published_packages > 1)
    messages = {
        title: "#{types} can't be disabled",
        description: "There #{is_plural ? "are" : "is" } #{pluralize(total_published_packages, "package")} already published that you need to delete before disabling the services."
    }
  end

  def disabled_warning_message(types_with_published_packages, total_published_packages)
    types = types_with_published_packages.to_sentence
    multiple_types = (types_with_published_packages.count > 1)

    is_plural = (total_published_packages > 1)
    messages = {
        title: "#{types} #{multiple_types ? "have" : "has"} packages published",
        description: "There #{is_plural ? "are" : "is"} #{pluralize(total_published_packages, "package")} that will be disabled but not deleted after disabling the services."
    }
  end
end
