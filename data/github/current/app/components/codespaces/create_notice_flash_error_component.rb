# typed: true
# frozen_string_literal: true

class Codespaces::CreateNoticeFlashErrorComponent < ApplicationComponent
  include CodespacesHelper
  include GitHub::Memoizer

  attr_reader :billable_owner, :user, :at_codespace_limit, :user_codespace_limit, :machine_type_unavailable,
              :unexpected_error, :base_image_unavailable, :codespace, :is_spoofed_commit, :closed_pull_request,
              :show_billable_owner, :show_user_errors, :show_repo_errors, :system_arguments

  def initialize(billable_owner:, user:, at_codespace_limit: false, codespace: nil, repository: nil, user_codespace_limit: nil, machine_type_unavailable: false, unexpected_error: false, is_spoofed_commit: false, base_image_unavailable: false, closed_pull_request: false, show_billable_owner: true, show_user_errors: true, show_repo_errors: true, system_arguments: {})
    @billable_owner = billable_owner
    @user = user
    @codespace = codespace
    @repository = repository
    @at_codespace_limit = at_codespace_limit
    @user_codespace_limit = user_codespace_limit
    @machine_type_unavailable = machine_type_unavailable
    @unexpected_error = unexpected_error
    @base_image_unavailable = base_image_unavailable
    @is_spoofed_commit = is_spoofed_commit
    @closed_pull_request = closed_pull_request
    @show_billable_owner = show_billable_owner
    @show_user_errors = show_user_errors
    @show_repo_errors = show_repo_errors
    @system_arguments = system_arguments
  end

  def render?
    notice_component.render?
  end

  memoize def notice_component
    Codespaces::CreateNoticeComponent.new(
      billable_owner: billable_owner,
      user: user,
      codespace: codespace,
      repository: @repository,
      at_codespace_limit: at_codespace_limit,
      user_codespace_limit: user_codespace_limit,
      machine_type_unavailable: machine_type_unavailable,
      unexpected_error: unexpected_error,
      base_image_unavailable: base_image_unavailable,
      is_spoofed_commit: is_spoofed_commit,
      closed_pull_request: closed_pull_request,
      show_billable_owner: show_billable_owner,
      show_user_errors: show_user_errors,
      show_repo_errors: show_repo_errors,
    )
  end

  def flash_scheme
    if notice_component.is_error?
      :danger
    else
      :default
    end
  end

  def icon
    return :stop if notice_component.is_error?

    if @billable_owner.user?
      :person
    else
      :organization
    end
  end
end
