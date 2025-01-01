# typed: true
# frozen_string_literal: true

class Businesses::Billing::AdvancedSecurity::LicensingComponent < ApplicationComponent
  DEFAULT_TYPE = :eligible
  TYPES = T.let([:eligible, :enabled].freeze, T::Array[Symbol])

  sig { returns String }
  attr_reader :description

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  class StatusComponent < ApplicationComponent
    attr_reader :system_arguments

    def initialize(**system_arguments, &block)
      @system_arguments = system_arguments
      @block = block
    end

    def call
      return if content.blank?

      system_arguments[:tag] ||= :div
      system_arguments[:px] ||= 4
      system_arguments[:pb] ||= 3
      system_arguments[:scheme] ||= :success
      system_arguments[:test_selector] ||= "advanced-security-license-status"

      icon = nil

      case system_arguments[:scheme]
      when :success then
        system_arguments[:color] ||= :success
        icon = :"check-circle"
      when :failure then
        system_arguments[:color] ||= :danger
        icon = :alert
      else
        system_arguments[:color] ||= :default
        icon = :info
      end

      render(
        Primer::Beta::Text.new(**system_arguments).with_content(
          safe_join([
            render(Primer::Beta::Octicon.new(icon: icon, mr: 1)),
            content,
          ])
        )
      )
    end
  end

  sig { params(description: String, system_arguments: Primer::SystemArgumentsValue).void }
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
    system_arguments[:px] = 4 unless system_arguments[:px]
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

  renders_one :status, StatusComponent

  def title
    system_arguments[:title] || "GitHub Advanced Security"
  end
end
