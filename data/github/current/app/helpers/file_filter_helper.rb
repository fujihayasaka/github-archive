# typed: true
# frozen_string_literal: true

module FileFilterHelper
  extend T::Helpers

  include DiffHelper

  FILE_TYPE_FILTER_PARAM = "file-filters".freeze
  SHOW_DELETED_FILES_FILTER_PARAM = "show-deleted-files".freeze
  SHOW_VIEWED_FILES_FILTER_PARAM = "show-viewed-files".freeze
  CODEOWNER_PARAM = "owned-by".freeze
  MANIFESTS_PARAM = "manifests".freeze
  EMPTY_TYPE_SELECTION = [""].freeze
  PARAM_TRUE_VALUE = "true".freeze
  PARAM_FALSE_VALUE = "false".freeze
  EMPTY_ARRAY = [].freeze

  abstract!

  sig { abstract.returns(T.any(ActionController::Parameters, Hash)) }
  def params; end

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  # File filter param is present but no types are selected
  def all_file_types_unselected?
    params[FILE_TYPE_FILTER_PARAM] == EMPTY_TYPE_SELECTION
  end

  def deleted_files_hidden?
    params[SHOW_DELETED_FILES_FILTER_PARAM] == PARAM_FALSE_VALUE
  end

  def viewed_files_hidden?
    params[SHOW_VIEWED_FILES_FILTER_PARAM] == PARAM_FALSE_VALUE
  end

  def manifest_files_active?
    params[MANIFESTS_PARAM] == PARAM_TRUE_VALUE
  end

  # Determine if 'Only files owned by you' filter is currently selected via URL params
  #
  # Returns boolean
  def only_owned_by_active?
    return false unless params[CODEOWNER_PARAM]
    return false unless T.unsafe(self).logged_in?
    params[CODEOWNER_PARAM].include?(current_user&.login)
  end

  # Returns any valid selected file types from the URL params
  #   valid_file_types - Array of file types to allow filtering against
  #
  # Returns Array of Strings or Empty Array
  def sanitized_selected_file_types(valid_file_types:)
    return EMPTY_ARRAY unless params[FILE_TYPE_FILTER_PARAM].instance_of?(Array)
    valid_file_types & params[FILE_TYPE_FILTER_PARAM]
  end

  # Determine if given file type is currently selected via URL params
  #   file_type - String
  #   valid_file_types - Array of file types to allow filtering against
  #
  # Returns boolean
  def is_selected_file_type?(file_type:, valid_file_types:)
    return true if !params[FILE_TYPE_FILTER_PARAM]
    return true if valid_file_types.blank?
    return false if all_file_types_unselected?

    sanitized_selected_types = sanitized_selected_file_types(valid_file_types: valid_file_types)
    if sanitized_selected_types.present?
      sanitized_selected_types.include?(file_type)
    else
      true
    end
  end

  # Determine if diff is currently selected via URL params
  #   path - String path of the diff file
  #   deleted - Boolean indicating whether the diff is a deletion.
  #   valid_file_types - Array of file types to allow filtering against
  #   codeowners - Boolean indicating whether codeowners filter is active
  #   viewed - Boolean indicating whether file has been marked as viewed
  #
  # Returns boolean indicating if the diff should be filtered
  def file_filtered?(path:, deleted:, valid_file_types:, codeowners: false, viewed: false)
    if !params[FILE_TYPE_FILTER_PARAM] && !deleted_files_hidden? && !viewed_files_hidden? && !codeowners && !manifest_files_active?
      return false
    end

    if codeowners
      true
    elsif manifest_files_active?
      !DependencyManifestFile.recognized_path?(path: path)
    elsif params[FILE_TYPE_FILTER_PARAM]
      return true if all_file_types_unselected?
      file_type = get_file_type(path)
      is_filtered_by_file_type = !is_selected_file_type?(file_type: file_type, valid_file_types: valid_file_types)
      is_filtered_by_file_type || (deleted_files_hidden? && deleted) || (viewed_files_hidden? && viewed)
    elsif viewed_files_hidden?
      viewed
    elsif deleted_files_hidden?
      deleted
    else
      false
    end
  end
end
