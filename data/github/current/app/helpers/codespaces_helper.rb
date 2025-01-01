# typed: true
# frozen_string_literal: true

module CodespacesHelper
  include HydroHelper

  def open_codespace_attributes(codespace:, target:)
    codespace_analytics \
      codespace: codespace,
      target: target,
      action: "open"
  end

  def create_codespace_attributes(codespace:, target:)
    codespace_analytics \
      codespace: codespace,
      target: target,
      action: "create"
  end

  def destroy_codespace_attributes(codespace:)
    codespace_analytics \
      codespace: codespace,
      target: :CODESPACES_PAGE,
      action: "destroy"
  end

  def suspend_codespace_attributes(codespace:)
    codespace_analytics \
      codespace: codespace,
      target: :CODESPACES_PAGE,
      action: "suspend"
  end

  def codespace_url_from_editor_preferences(codespace:, user:)
    codespace_url_from_editor(codespace: codespace, editor: user.codespace_preferred_editor)
  end

  def codespace_url_from_editor(codespace:, editor:)
    case editor
    when Codespaces::Settings::PREFERRED_EDITOR_VSCODE_WEB
      T.unsafe(self).codespace_path(codespace)
    else
      T.unsafe(self).codespace_path(codespace, editor: editor)
    end
  end

  def should_add_editor_query_parameter?
    # We only want to add the editor query parameter if the user's preferred
    # editor is a non-VS Code web editor.
    Codespaces::Settings::WEB_EDITORS.include?(T.unsafe(self).current_user.codespace_preferred_editor) &&
      T.unsafe(self).current_user.codespace_preferred_editor != Codespaces::Settings::PREFERRED_EDITOR_VSCODE_WEB
  end

  def codespace_usage(codespace)
    usage = Codespaces::AccessChecker.from_codespace(codespace)

    usage.run_check(
      sku_name: codespace.sku_name,
      dev_container: codespace.dev_container,
    )
  end

  def codespaces_billing_enabled?(account)
    Codespaces::BillingPolicy.billing_feature_enabled?(account)
  end

  def formatted_codespace_display_name(codespace:)
    case codespace.vscs_target
    when :production
      codespace.safe_display_name
    when :ppe
      codespace.safe_display_name + " ✨"
    else
      codespace.safe_display_name + " 🚧"
    end
  end

  private

  def codespace_analytics(codespace:, target:, action:)
    payload = {
      ref: codespace.ref,
      repository_id: codespace.repository_id,
      pull_request_id: codespace.pull_request_id,
      target: target,
      user_id: T.unsafe(self).current_user.id,
      codespace_id: codespace.id
    }
    hydro_click_tracking_attributes("codespace_#{action}.click", payload)
  end
end
