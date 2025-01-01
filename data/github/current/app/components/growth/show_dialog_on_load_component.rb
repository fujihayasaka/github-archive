# typed: strict
# frozen_string_literal: true

class Growth::ShowDialogOnLoadComponent < ApplicationComponent
  extend T::Sig

  sig { returns String }
  attr_reader :url_param

  sig { returns T::Boolean }
  attr_reader :display

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig do
    params(
      url_param: String,
      display: T::Boolean,
      system_arguments: T.untyped,
    ).void
  end
  def initialize(url_param: "", display: false, **system_arguments)
    @url_param = url_param
    @display = display
    @system_arguments = system_arguments
  end

  renders_one :dialog, lambda { |**system_arguments|
    arguments = system_arguments
    arguments[:data] = {
      "target": "show-dialog-on-load.dialog",
    }.merge(system_arguments[:data] || {})
    Primer::Alpha::Dialog.new(
      **arguments
    )
  }
end
