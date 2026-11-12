# frozen_string_literal: true

class ClipboardCopyComponent < ApplicationComponent
  attr_reader :system_arguments

  def initialize(**system_arguments)
    @system_arguments = system_arguments
    @system_arguments[:classes] ||= ""
    @system_arguments[:classes] += " no-outline color-fg-muted Link--onHover tooltipped-no-delay"
    @system_arguments[:"aria-label"] ||= "Copy"
    @system_arguments[:"data-copy-feedback"] ||= "Copied!"
    @system_arguments[:"data-tooltip-direction"] ||= "n"
  end
end
