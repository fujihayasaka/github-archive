# typed: true
# frozen_string_literal: true

class CodeScanning::ToolStatus::HeaderComponent < ApplicationComponent
  renders_one :subtitle

  def initialize(href:, label:, **kwargs)
    @href = href
    @label = label
    @kwargs = kwargs
  end
end
