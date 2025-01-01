# typed: true
# frozen_string_literal: true

class Codespaces::AllowPermissionsCreateButtonComponent < Codespaces::CreateButtonComponent
  renders_one :additional_hidden_fields
  attr_reader :btn_options

  def form_options
    {
      html: {
        class: form_classes,
        "data-target": data_target,
        "data-action": "pollvscode:get-repo#pollForVscode " \
                      "pollvscode:new-codespace#pollForVscode " \
                      "prpollvscode:create-button#pollForVscode",
        role: "form",
        data: data.merge({ turbo: false })
      }.merge(test_selector_data_hash("codespaces-create-form"))
    }
  end

  def init_js_vscode_form
    open_in_deeplink
  end

  def initialize(btn_options: {}, **kwargs)
    super(**T.unsafe(kwargs))
    @btn_options = btn_options
  end
end
