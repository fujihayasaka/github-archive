# typed: true
# frozen_string_literal: true

class Codespaces::QuickStartComponent < ApplicationComponent
  include AvatarHelper
  include CodespacesHelper

  attr_reader :quickstart_codespace, :auto_init, :devcontainer

  delegate :billable_owner, :ref, :pull_request_id, :devcontainer_path, to: :quickstart_codespace

  renders_one :form_content

  def initialize(quickstart_codespace:, auto_init: false, validator: nil, devcontainer: nil)
    @quickstart_codespace = quickstart_codespace
    @validator = validator
    @auto_init = !!auto_init
    @devcontainer = devcontainer
  end

  def render?
    logged_in?
  end

  def creations_should_be_disabled?
    return true if has_unsatisfied_cap?

    # If we're fully valid yay!
    return false if validator.valid?

    # If we're auto-initializing the repository then we don't need a valid OID because we can't have one yet.
    return false if auto_init? && validator.errors.include?(:oid)

    # Otherwise we should disable creations
    true
  end

  def has_unsatisfied_cap?
    return false unless billable_owner

    cap_filter.unauthorized([billable_owner]).any?
  end

  memoize def is_resumable?
    quickstart_codespace.persisted? && quickstart_codespace.provisioned?
  end

  memoize def machine_type_unavailable
    validator.errors.include?(:machine)
  end

  memoize def base_image_unavailable
    validator.errors.include?(:base_image)
  end

  memoize def closed_pull_request
    validator.errors.include?(:pull_request)
  end

  def auto_init?
    current_user.feature_enabled?(:codespaces_empty_repo_init) && auto_init
  end

  def advanced_options_link
    extra_params = {
      skip_quickstart: true,
      hide_repo_select: true,
    }
    if params[:template] == "false"
      extra_params[:template] = false
    end
    new_codespace_path(
      repo: quickstart_codespace.repository.id,
      ref: quickstart_codespace.ref || quickstart_codespace.pull_request&.head_ref,
      devcontainer_path: quickstart_codespace.devcontainer_path,
      **extra_params
    )
  end

  def click_tracking_attributes
    create_codespace_attributes(codespace: quickstart_codespace, target: "QUICKSTART")
  end

  def resume_tracking_attributes
    open_codespace_attributes(codespace: quickstart_codespace, target: "QUICKSTART_RESUME")
  end

  memoize def open_directly_in_a_non_web_editor?
    Codespaces::Settings.for_user(current_user).prefers_non_web_editor?
  end

  memoize def resume_url
    codespace_url_from_editor_preferences(codespace: quickstart_codespace, user: current_user)
  end

  def repository
    if quickstart_codespace.pull_request
      # When dealing with a pull request we want to _display_ the base repository in the QuickStartComponent.
      # The form will still end up using the quickstart_codespace.repository which will be set to the head repository.
      quickstart_codespace.pull_request.base_repository
    else
      quickstart_codespace.repository
    end
  end

  memoize def permissions_need_allowance?
    devcontainer&.permissions_need_allowance?
  end

  def form_kwargs
    args = { model: quickstart_codespace, class: class_names("js-toggle-hidden-codespace-form", { "js-open-in-vscode-form": open_directly_in_a_non_web_editor? }), data: { action: "pollvscode:new-codespace#pollForVscode" } }
    return args unless current_user.feature_enabled?(:codespaces_quickstart_permissions)
    if permissions_need_allowance?
      args[:url] = allow_permissions_codespaces_path
    end
    args
  end

  private

  memoize def validator
    return @validator if @validator

    location = Codespaces::GetRegionForUser.call(
      user: current_user,
      repository:,
    )
    # Imagine we pulled out the validations we run in Create and allowed them to be used independently here and elsewhere.
    # To do so we'd also have to make sure the errors we add to the "model" from those validations can be rendered properly
    # in e.g. the CreateNoticeFlashErrorComponent.
    Codespaces::Create.new(attributes: {
      owner: current_user,
      repository_id: repository.id,
      ref:,
      pull_request_id:,
      devcontainer_path:,
      location:
    }).tap(&:valid?)
  end
end
