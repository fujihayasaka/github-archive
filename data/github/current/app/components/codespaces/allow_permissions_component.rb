# typed: true
# frozen_string_literal: true

class Codespaces::AllowPermissionsComponent < ApplicationComponent
  renders_one :footer

  ADDITIONAL_PERMISSIONS_REQUIRED = GitHub::HTMLSafeString.make("This codespace is requesting<br>additional permissions")
  PREBUILD_ADDITIONAL_PERMISSIONS_REQUIRED = GitHub::HTMLSafeString.make("This prebuild configuration is requesting<br>additional permissions")

  attr_reader :devcontainer, :repo_readable_by_user_count, :create_button_params

  def initialize(devcontainer:, repo_readable_by_user_count: nil, create_button_params: {}, is_prebuild: false, branch: nil)
    @devcontainer = devcontainer
    @repo_readable_by_user_count = repo_readable_by_user_count
    @create_button_params = create_button_params
    @is_prebuild = is_prebuild
    @branch = branch
  end

  # [
  #   ["monalisa/* (5 repositories)", {"contents"=>"write"}],
  #   ["monalisa/smile", {"contents"=>"read"}]
  # ]
  def permissions
    permissions_array = repository_permissions
    all_repository_permissions.each do |owner, permissions|
      permissions_array.prepend(["#{owner.display_login}/* (#{pluralize(repo_readable_by_user_count, "repository")})", permissions])
    end
    permissions_array
  end

  def repository_permissions
    devcontainer.repository_permissions.map { |repo, permissions| [repo.name_with_display_owner, permissions] }
  end

  def revoked_permissions
    diff_all_permissions.revoked.transform_keys do |target|
      if target.respond_to?(:nwo)
        target.name_with_display_owner
      else
        "#{target.display_login}/* (#{pluralize(repo_readable_by_user_count, "repository")})"
      end
    end
  end

  def title
    if diff_all_permissions.only_revoked_permissions?
      return "This prebuild configuration has updated permissions" if @is_prebuild
      "This codespace has updated permissions"
    elsif @is_prebuild
      PREBUILD_ADDITIONAL_PERMISSIONS_REQUIRED
    else
      ADDITIONAL_PERMISSIONS_REQUIRED
    end
  end

  def authorize_button_text
    if diff_all_permissions.only_revoked_permissions?
      return "Continue and create codespace" unless @is_prebuild
      "Continue and create prebuild"
    else
      "Authorize and continue"
    end
  end

  def branch_dispaly_text
    Git::Ref.value_for_display(@branch)
  end

  def inner_box_text
    if @is_prebuild
      "Your prebuild configuration for #{branch_dispaly_text} is requesting the following permissions for these repositories:"
    else
      "Your codespace is requesting the following permissions for these repositories:"
    end
  end

  delegate :all_repository_permissions, to: :devcontainer
  delegate :unknown_repository_permissions, to: :devcontainer
  delegate :diff_all_permissions, to: :devcontainer
end
