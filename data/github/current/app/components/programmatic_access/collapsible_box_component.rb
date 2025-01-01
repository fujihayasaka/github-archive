# typed: strict
# frozen_string_literal: true

class ProgrammaticAccess::CollapsibleBoxComponent < ApplicationComponent
  include Primer::ClassNameHelper
  renders_one :header, -> (**system_arguments) do
    system_arguments[:tag] = :div
    Primer::BaseComponent.new(**system_arguments)
  end

  renders_one :body, -> (**system_arguments) do
    Primer::Beta::BorderBox.new(**system_arguments, classes: T.bind(self, ProgrammaticAccess::CollapsibleBoxComponent).body_classes)
  end

  sig { returns(T.untyped) }
  attr_reader :id, :header_bg, :mb

  sig { params(id: T.nilable(String), header_bg: Symbol, mb: Integer, system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(id: nil, header_bg: :subtle, mb: 3, **system_arguments)
    @id = id
    @header_bg = header_bg
    @mb = mb
  end

  sig { returns(String) }
  def body_classes
    class_names(
      "js-collapsible-body",
      "rounded-top-0",
      "rounded-bottom-2",
      "border-0 border-top color-bg-subtle"
    )
  end
end
