# typed: true
# frozen_string_literal: true

class Codespaces::LoadingComponent < ApplicationComponent

  attr_reader :codespace, :header_text, :repository

  def initialize(codespace:, header_text: "Preparing your codespace", repository: nil, loading_state: nil)
    @codespace = codespace
    @repository = repository
    @header_text = header_text
    @loading_state = loading_state
  end

  memoize def container_classes
    "container log-fullscreen color-mode-enabled"
  end

  # This value is used to initialize a view loading state. For the iframed flow, this value is updated as loading
  # progresses in codespaces.ts to display loading progress to the user.
  # We will likely revisit or remove this when we remove the iframed flow.
  def loading_state
    @loading_state || codespace.stuck_provisioning? ? "stuck" : codespace.state
  end
end
