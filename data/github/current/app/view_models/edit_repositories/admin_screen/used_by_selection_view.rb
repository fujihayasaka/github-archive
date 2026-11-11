# typed: true
# frozen_string_literal: true

class EditRepositories::AdminScreen::UsedBySelectionView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :repository, :packages

  # Should we display the view for someone to change their package?
  # Only if used by is enabled and they've got more than one package.
  #
  # Returns bool
  def should_be_rendered?
    repository.used_by_enabled? && packages.present? && packages.length > 1
  end

  # Helper to decide what text to display for our button.
  # If there's a package already specified we want to display that, else we'll get the default name (first package).
  def button_text
    has_package_selection? ? currently_selected_package_name : default_package_name
  end

  # Helper to check if a used_by_package_id config exists on the repo.
  # Returns bool
  def has_package_selection?
    currently_selected_package.present?
  end

  # Helper to get the current used_by_package_id config on the repo.
  def currently_selected_package
    repository.used_by_package_id
  end

  # Helper to get the current used_by_package_id config on the repo.
  def currently_selected_package_name
    @selected_package ||= packages.find { |p| p.id == currently_selected_package }
    @selected_package&.name || "Select package"
  end

  # Helper to get the default package selection name, which would be the first package returned from Dependency Graph.
  def default_package_name
    packages.first.name
  end

  # Use packages data to populate an Array of options for front-end display.
  def package_list
    return @package_list if defined?(@package_list)

    @package_list = packages.reduce([]) do |output, package|
      # Don't return packages with names that are too long to persist in the DB.
      next output if package.name.length > Configuration::Entry::VALUE_MAX_LENGTH

      output << {
        id: package.id,
        name: package.name,
        count: package.repository_dependents_count,
        selected: package_selected?(package),
        package_manager: package.package_manager_human_name,
      }
    end
  end

  private

  # Helper to determine if the package is selected.
  # If the user already has specified a package selection, we'll check that else we'll compare against the default.
  def package_selected?(package)
    if has_package_selection?
      package.id == currently_selected_package
    else
      package.name == default_package_name
    end
  end
end
