# typed: true
# frozen_string_literal: true
class Businesses::Billing::AdvancedSecurity::LicensingComponent < ApplicationComponent
  extend T::Sig

  DEFAULT_TYPE = :eligible
  TYPES = T.let([:eligible, :enabled].freeze, T::Array[Symbol])

  sig { returns String }
  attr_reader :description

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { params(description: String, system_arguments: T.untyped).void }
  def initialize(description: "", **system_arguments)
    @description = description
    @system_arguments = system_arguments
    @system_arguments[:classes] = class_names(
      "Box",
      system_arguments[:classes]
    )
  end

  renders_one :body, lambda { |**system_arguments|
    system_arguments[:tag] = :div
    system_arguments[:display] = :flex unless system_arguments[:display]
    system_arguments[:align_items] = :center unless system_arguments[:align_items]
    system_arguments[:color] = :muted unless system_arguments[:color]
    system_arguments[:classes] = "Box-row" unless system_arguments[:classes]
    Primer::BaseComponent.new(**system_arguments)
  }

  renders_one :control, lambda { |**system_arguments|
    system_arguments[:tag] = :div
    system_arguments[:display] = :flex unless system_arguments[:display]
    system_arguments[:align_items] = :center unless system_arguments[:align_items]
    Primer::BaseComponent.new(**system_arguments)
  }

  renders_one :banner, lambda { |**banner_arguments|
    banner_arguments[:full] ||= true
    Primer::Alpha::Banner.new(**banner_arguments)
  }

  def title
    system_arguments[:title] || "GitHub Advanced Security"
  end
end
