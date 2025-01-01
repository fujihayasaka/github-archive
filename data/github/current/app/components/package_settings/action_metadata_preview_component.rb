# typed: true
# frozen_string_literal: true

class PackageSettings::ActionMetadataPreviewComponent < ApplicationComponent
  include RepositoryActionHelper

  def render?
    return false if !GitHub.marketplace_enabled?
    return false if !GitHub.flipper[:action_package_marketplace].enabled?(current_user)
    true
  end

  def initialize(action:, action_package_listed:)
    @action = action
    @action_package_listed = action_package_listed
  end

  attr_reader :action, :action_package_listed

  memoize def metadata_file_name
    File.basename(@action.path)
  end

  memoize def action_owner
    action.repository.owner_display_login
  end

  memoize def metadata_file_values
    # We load in the values from the metadata file to show the user any issues with
    # how they setup their labels.
    @metadata_file_values ||= action.config_from_metadata_file
  end
end
