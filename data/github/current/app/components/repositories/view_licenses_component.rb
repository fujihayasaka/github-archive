# typed: true
# frozen_string_literal: true

class Repositories::ViewLicensesComponent < ApplicationComponent
  attr_reader :repository, :repository_licenses

  LICENSE_FILENAME_REGEXP = RepositoryLicense::FILENAME_REGEXP

  def initialize(repository:, options: {}, current_directory: nil)
    @repository = repository
    return unless repository

    @repository_licenses = set_visible_repository_licenses(repository.repository_licenses)
    @licenses_count = repository_licenses.length
    @options = options
    @current_directory = current_directory
  end

  def render?
    repository_present? && has_licenses? && all_licenses_have_spdx_id? && has_preferred_license_path?
  end

  def current_repository
    repository
  end

  def multi_license?
    @licenses_count > 1
  end

  def license_text
    license = repository.license
    if license.other?
      "View license"
    else
      "#{license.spdx_id} license"
    end
  end

  def license_hash
    license = repository.license
    if license.other?
      "License-1-ov-file"
    else
      "#{license.spdx_id}-1-ov-file"
    end
  end

  def multiple_licenses_text
    return two_licenses_text if @licenses_count == 2

    remaining_license_count = repository_licenses.count - 1
    "#{license_spdx(repository.license)} and #{remaining_license_count} other licenses found"
  end

  def filepath_for(license_filepath)
    license_filepath&.gsub("./", "")
  end

  def license_spdx(license)
    if license.other?
      "Unknown"
    else
      license.spdx_id
    end
  end

  def on_default_branch?
    @current_directory&.commitish == repository.default_branch
  end

  memoize def selector_classes
    @options[:selector_classes] || ""
  end

  private

  def two_licenses_text
    repository_licenses.map do |repository_license|
      license = repository_license.license
      license_spdx(license)
    end.join(", ") + " licenses found"
  end

  def set_visible_repository_licenses(repository_licenses)
    repository_licenses.reject { |repository_license| is_not_viewable?(repository_license) }
  end

  def repository_present?
    repository.present?
  end

  def has_licenses?
    @licenses_count > 0
  end

  def all_licenses_have_spdx_id?
    repository_licenses.map(&:license).all? { |license| license.spdx_id.present? }
  end

  def has_preferred_license_path?
    repository.preferred_license.try(:path).present?
  end

  def is_not_viewable?(repository_license)
    repository_license.license.other? && filename_not_license_like?(repository_license)
  end

  def filename_not_license_like?(repository_license)
    # Licenses without filepaths will fallback to the preferred_file, so we can render those
    filepath = repository_license.filepath
    return false unless filepath.present?

    filename = filepath.split("/").last
    filename.match(LICENSE_FILENAME_REGEXP).nil?
  end
end
