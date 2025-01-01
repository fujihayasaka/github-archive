# typed: true
# frozen_string_literal: true

class Billing::Settings::Upgrade::SectionComponent < ApplicationComponent
  extend T::Sig

  sig { returns String }
  attr_reader :title

  sig { returns(T.any(Symbol, String)) }
  attr_reader :icon

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { params(title: String, icon: T.any(Symbol, String), system_arguments: T.untyped).void }
  def initialize(title:, icon:, **system_arguments)
    @title = title
    @icon = icon
    @system_arguments = system_arguments
  end

  renders_one :body, lambda { |**system_arguments|
    system_arguments[:tag] = :div
    system_arguments[:w] = :full
    Primer::BaseComponent.new(**system_arguments)
  }

  renders_one :button, lambda { |**system_arguments|
    Primer::Beta::Button.new(**system_arguments)
  }

end
