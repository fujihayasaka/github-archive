# typed: true
# frozen_string_literal: true

class Codespaces::CreateButtonComponent < ApplicationComponent
  include ResilienceHelper

  attr_reader :codespace, :geo, :vscs_target, :vscs_target_url, :sku, :text, :block, :btn_class, :button_icon, :icon_class, :data, :wide, :open_in_deeplink, :default_sku, :open_in_new_tab, :dropdown, :hide_location
  # codespace                       - The codespace to be created. Should be built with a `repository` and either a `ref` or `pull_request_id`.
  # geo                             - The geo to create the codespace within
  # vscs_target                     - The VSCS environment where this codespace should be created (optional, default: nil)
  # vscs_target_url                 - The specific URL to be passed to the codespace, used by VSCS devs (optional, default: nil)
  # sku                             - The SKU chosen by the user or by default (optional Codespaces::Sku object, default: nil).
  # text                            - a button text String. (optional, default: "Open in codespace")
  # block                           - a boolean whether button is full-width with `display: block` (optional, default: false)
  # btn_class                       - a CSS class String to use for the button element. (optional, default: "btn")
  # icon_class                      - CSS class passed to the Primer::Beta::Octicon helper (optional, default: "")
  # data                            - a Hash for collecting keys/values that will be rendered as data attributes. (optional, default: {})
  # wide                            - A boolean, used to render tooltip on list component (disabled for wide component)
  # open_in_deeplink                - when truthy this appends a hidden `open_in_deeplink` param to the codespace create form
  # skip_permissions_check          - when truthy, bypasses the redirect to the allow_permissions flow
  # dropdown                        - when truthy, shows dropdown with link to advanced creation options
  # hide_location                   - when truthy, don't specify/pass up a location for the codespace
  def initialize(
    codespace:,
    geo: nil,
    vscs_target: nil,
    vscs_target_url: nil,
    sku: nil,
    text: "Open in codespace",
    block: false,
    btn_class: "",
    icon_class: "",
    data: {},
    wide: false,
    open_in_deeplink: false,
    devcontainer: nil,
    skip_permissions_check: nil,
    open_in_new_tab: true,
    dropdown: false,
    hide_location: false
  )
    @codespace, @geo, @vscs_target, @vscs_target_url, @sku, @text, @block, @btn_class, @icon_class, @data, @wide, @open_in_deeplink, @devcontainer, @skip_permissions_check, @open_in_new_tab, @dropdown, @hide_location =
      codespace, geo, vscs_target, vscs_target_url, sku, text, block, btn_class, icon_class, data, wide, open_in_deeplink, devcontainer, skip_permissions_check, open_in_new_tab, dropdown, hide_location
  end

  renders_one :loading_button
  renders_one :disabled_button

  def form_options
    options = {
      html: {
        class: form_classes,
        "data-turbo": false,
        "data-target": data_target,
        "data-action": "pollvscode:get-repo#pollForVscode " \
                      "pollvscode:new-codespace#pollForVscode " \
                      "prpollvscode:create-button#pollForVscode",
        data: data
      }.merge(test_selector_data_hash("codespaces-create-form"))
    }
    if permissions_need_allowance
      options[:url] = allow_permissions_codespaces_path #submit form to devcontainer permission flow
    end

    if open_in_new_tab
      options[:html][:target] = "_blank"
    end

    options
  end

  def form_classes
    class_names(
      "js-create-codespaces-form-command",
      "d-flex",
      "width-full",
      {
        "js-toggle-hidden-codespace-form": init_js_vscode_form,
        "js-open-in-vscode-form": init_js_vscode_form, # This class causes the form submit to be handled by JS
      },
    )
  end

  def init_js_vscode_form
    open_in_deeplink && !permissions_need_allowance
  end

  def subtext_class
    "text-small text-normal color-fg-muted pl-4 mb-0"
  end

  def subtext_text
    "Use powerful compute to debug, test, and run code"
  end

  def data_target
    "get-repo.codespaceForm new-codespace.createCodespaceForm"
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
    return false if @skip_permissions_check #this component is also used in permissions flow, so need a way to break the loop

    devcontainer&.permissions_need_allowance?
  end

  def hide_advanced_options_button
    sku && valid_image
  end

  memoize def valid_image
    Codespaces::ImagePolicy.image_allowed?(
      image_name: devcontainer&.image,
      repository: codespace.repository,
      billable_owner: codespace.billable_owner
    )
  end
end
