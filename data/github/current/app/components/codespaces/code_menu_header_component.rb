# typed: true
# frozen_string_literal: true

module Codespaces
  class CodeMenuHeaderComponent < ApplicationComponent
    include ResilienceHelper
    include CodespacesHelper

    attr_reader :codespace, :repository, :repository_policy, :current_user, :user_id, :open_in_deeplink, :default_sku, :cap_filter, :at_limit, :is_spoofed_commit, :missing_head_ref, :missing_head_repo

    # codespace     - The codespace to be created. Should be built with a `repository` and either a `ref` or `pull_request_id`.
    def initialize(codespace:,
                   repository:,
                   repository_policy:,
                   current_user:,
                   user_id:,
                   open_in_deeplink:,
                   default_sku: nil,
                   cap_filter:,
                   at_limit:,
                   is_spoofed_commit: false,
                   missing_head_ref:,
                   missing_head_repo:
                  )
      @codespace, @repository, @repository_policy, @current_user, @user_id, @open_in_deeplink, @default_sku, @cap_filter, @at_limit, @is_spoofed_commit, @missing_head_ref, @missing_head_repo = codespace, repository, repository_policy, current_user, user_id, open_in_deeplink, default_sku, cap_filter, at_limit, is_spoofed_commit, missing_head_ref, missing_head_repo
    end

    def creations_should_be_disabled?
      GitHub.flipper[:disable_codespace_creation].enabled?(current_user) ||
        !can_attempt_create? ||
        disable_at_limit? ||
        !usage_allowed? ||
        at_total_usage_limit? ||
        has_unsatisfied_cap? ||
        is_spoofed_commit ||
        missing_head_ref ||
        missing_head_repo ||
        closed_pull_request?
    end

    memoize def can_attempt_create?
      repository_policy.can_attempt_create?
    end

    # User has hit the limit of codespaces they can create at any one time?
    def disable_at_limit?
      at_limit
    end

    def usage_allowed?
      return true if codespace.nil?
      usage.allowed_by_billing?
    end

    memoize def at_total_usage_limit?
      if usage&.allowed_by_billing?
        false
      elsif current_user.organization_ids.empty? # if the user has no usage allowed and no organizations then we are total usage limit
        true
      else
        # if any of the user's organizations have usage allowed then we are not at total usage limit
        !current_user.organizations.any? do |org|
          Codespaces::AccessChecker.new(org, user: current_user).allowed_by_billing?
        end
      end
    end

    def has_unsatisfied_cap?
      return false unless codespace

      cap_filter.unauthorized([codespace]).any?
    end

    memoize def new_with_options_link
      extra_params = {
        hide_repo_select: true,
        skip_quickstart: true,
      }
      if repository&.template?
        extra_params[:template] = false
      end
      new_codespace_path(repo: codespace.repository_id, ref: display_ref, **extra_params)
    end

    private

    memoize def closed_pull_request?
      codespace.pull_request&.closed?
    end

    def usage
      return nil if codespace.nil?

      @usage ||= Codespaces::AccessChecker.from_codespace(codespace)
    end

    def form_options
      options = {
        html: {
          class: form_classes,
          "data-target": "get-repo.codespaceForm new-codespace.createCodespaceForm",
          "data-action": "pollvscode:get-repo#pollForVscode " \
                        "pollvscode:new-codespace#pollForVscode " \
                        "prpollvscode:create-button#pollForVscode",
          target: "_blank",
          id: "create_codespace_form_plus",
        }.merge(test_selector_data_hash("codespaces-code-dropdown-header-create-form"))
      }
      if permissions_need_allowance
        options[:url] = allow_permissions_codespaces_path #submit form to devcontainer permission flow
      end

      options
    end

    def form_classes
      class_names(
        "js-toggle-hidden-codespace-form",
        "js-create-codespaces-form-command",
        {
          "js-open-in-vscode-form": init_js_vscode_form, # This class causes the form submit to be handled by JS
        },
      )
    end

    def init_js_vscode_form
      open_in_deeplink && !permissions_need_allowance
    end

    memoize def devcontainer
      return @devcontainer if @devcontainer.present?

      with_database_error_fallback do
        devcontainer_path = codespace.devcontainer_path.presence
        ref = codespace.ref || codespace.pull_request&.head_ref
        ref_for_oid = Codespaces::GetTargetRef.call(repository: codespace.repository, name_or_oid: ref) if ref

        if target_oid = ref_for_oid&.target_oid
          Codespaces::DevContainer.new(
            repository: codespace.repository,
            oid: target_oid,
            filepath: devcontainer_path,
            user: current_user
          )
        end
      end
    end

    memoize def permissions_need_allowance
      @_permissions_need_allowance ||= check_permissions_need_allowance
    end

    def check_permissions_need_allowance
      devcontainer&.permissions_need_allowance?
    end

    memoize def show_configure_prebuilds?
      repository_policy.can_modify_codespace_repo_settings?
    end

    memoize def show_configure_dev_container?
      return false unless repository_policy.can_attempt_create?(allow_forking: true) # Can fork or push to the repo.
      return false unless create_or_edit_dev_container_path&.present?
      true
    end

    def tooltip_text
      if disable_one_click_creation
        "Configure and create a codespace"
      else
        tooltip = "Create a codespace"
        tooltip += " on #{display_ref}" if display_ref
        tooltip
      end
    end

    memoize def display_ref
      ref = codespace.ref || codespace.pull_request&.head_ref || ""
      Git::Ref.value_for_display(ref)
    end

    # Returns the path that the 'Configure Dev Container' button should link to.
    memoize def create_or_edit_dev_container_path
      with_database_error_fallback do
        if branch_ref = repository.refs.find(codespace.ref)
          # If the ref is a branch, we want to link to the branch's edit page.
          # This will ignore tags, for instance.
          if branch_ref&.prefix == "refs/heads/" && oid = branch_ref&.target_oid
            return calculate_create_or_edit_dev_container_path(codespace.ref, oid)
          end
        end

        # If we're detached from a branch or otherwise don't have a 'codespace.ref',
        # fallback to creating dev container on default branch.
        if branch_ref = repository.refs.find(repository.default_branch)
          calculate_create_or_edit_dev_container_path(repository.default_branch,  branch_ref&.target_oid)
        end
      end
    end

    # Helper method
    # Detects the presence of a devcontainer.json file,
    # and returns the appropriate path for 'create_or_edit_dev_container_path()'
    def calculate_create_or_edit_dev_container_path(target_branch, target_oid)
      dev_container_path_on_branch_if_exists = Codespaces::DevContainer.get_default_path(repository, target_oid)

      # Open devcontainer.json in 'codespaces_dev_container_wizard'
      if dev_container_path_on_branch_if_exists.present?
        file_edit_path(repository.owner, repository, target_branch, dev_container_path_on_branch_if_exists)
      else
        new_file_path(repository.owner, repository, target_branch, filename: ".devcontainer/devcontainer.json", dev_container_template: 1)
      end
    end

    def disable_one_click_creation
      !default_sku || !valid_image
    end

    memoize def valid_image
      return true unless devcontainer.present? && codespace.present?

      Codespaces::ImagePolicy.image_allowed?(
        image_name: devcontainer.image,
        repository: codespace.repository,
        billable_owner: codespace.billable_owner
      )
    end

    memoize def click_tracking_attributes
      target = if codespace.pull_request.present?
        "PULL_REQUEST_PAGE_DROPDOWN"
      else
        "REPO_PAGE_DROPDOWN"
      end
      create_codespace_attributes(codespace:, target:)
    end
  end
end
