# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class AccessGroupings::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  extend T::Helpers
  abstract!

  def single_file_access?
    permissions.has_key?("single_file")
  end

  def single_file_access
    access = permissions["single_file"].to_s.capitalize
    octicon = helpers.octicon("check", class: "color-fg-success mr-1")

    builder = []
    builder << helpers.content_tag(:span, octicon) # rubocop:disable Rails/ViewModelHTML
    builder << " "
    builder << helpers.content_tag(:strong, access) # rubocop:disable Rails/ViewModelHTML
    builder << " "
    builder << "access to files located at "

    current_version.single_file_paths.each_with_index do |path, index|
      builder << helpers.content_tag(:code, path) # rubocop:disable Rails/ViewModelHTML
      builder << ", " unless index == current_version.single_file_paths.length - 1
    end

    helpers.safe_join(builder)
  end

  def read_access(user_permissions_only: false)
    integration_permissions = user_permissions_only ? user_permissions : permissions
    access = access_with_permission_to(integration_permissions, :read)
    if access.any?
      names = format_permission_names(access.keys)
      helpers.safe_join([helpers.content_tag(:strong, "Read"), " ", "access to #{names}"]) # rubocop:disable Rails/ViewModelHTML
    end
  end

  def write_access(user_permissions_only: false)
    integration_permissions = user_permissions_only ? user_permissions : permissions
    access = access_with_permission_to(integration_permissions, :write)
    if access.any?
      names = format_permission_names(access.keys)
      helpers.safe_join([helpers.content_tag(:strong, "Read"), " and ", helpers.content_tag(:strong, "write"), " ", "access to #{names}"]) # rubocop:disable Rails/ViewModelHTML
    end
  end

  def admin_access(user_permissions_only: false)
    integration_permissions = user_permissions_only ? user_permissions : permissions
    access = access_with_permission_to(integration_permissions, :admin)
    if access.any?
      names = format_permission_names(access.keys)
      helpers.safe_join([helpers.content_tag(:strong, "Admin"), " ", "access to #{names}"]) # rubocop:disable Rails/ViewModelHTML
    end
  end

  # Internal: Memoize the permissions.
  #
  # Returns the organization and repository permission Hash
  def permissions
    {}
  end

  # Internal: Memoize the permissions.
  #
  # Returns the user permission Hash
  def user_permissions
    {}
  end

  def content_references
    integration.default_content_references.keys
  end

  sig { abstract.returns(IntegrationVersion) }
  def current_version; end

  private

  def format_permission_names(keys)
    names = Permissions::FineGrainedResources::Metadata.human_readable_resource_names.values_at(*keys)
    names.compact.sort.to_sentence
  end

  def access_with_permission_to(integration_permissions, action)
    integration_permissions.select { |k, v| v == action && k != "single_file" }
  end

  sig { abstract.returns(Integration) }
  def integration; end
end
