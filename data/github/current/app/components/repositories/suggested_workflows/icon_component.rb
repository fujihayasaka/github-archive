# typed: strict
# frozen_string_literal: true
class Repositories::SuggestedWorkflows::IconComponent < ApplicationComponent
  DEFAULT_OCTICON = "tools"
  DEFAULT_SIZE = :small
  SIZES = T.let([:small, :medium, :large].freeze, T::Array[Symbol])
  ICON_MAPPINGS = T.let({
    small: "width: 32px !important; height: 32px !important; min-width: 32px !important;",
    medium: "width: 48px !important; height: 48px !important; min-width: 48px !important;",
    large: "width: 64px !important; height: 64px !important; min-width: 64px !important;",
  }.freeze, T::Hash[Symbol, String])

  sig { returns RepositoryActions::Onboarding::Template }
  attr_reader :template

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { params(name: String).returns(String) }
  def icon(name: template.icon_name)
    icon_name = name.split[1]
    return icon_name.split(".").first if icon_name
    DEFAULT_OCTICON #return this octicon if we have a malformed name
  end

  sig { params(template: RepositoryActions::Onboarding::Template, size: Symbol, system_arguments: T.untyped).void }
  def initialize(template:, size: :small, **system_arguments)
    @template = template
    @system_arguments = system_arguments
    @system_arguments[:tag] = :div
    @system_arguments[:classes] = class_names(@system_arguments[:classes], "CircleBadge")
    icon_size = T.let(fetch_or_fallback(SIZES, size, DEFAULT_SIZE), Symbol)
    @system_arguments[:style] = "color: #{icon_color} !important; background-color: var(--bgColor-white, var(--color-scale-white)) !important; #{ICON_MAPPINGS[icon_size]}" unless @system_arguments[:style]
  end

  private

  sig { returns(String) }
  def icon_color
    # Actions Importer does not have a lang_color, and we don't want to use the fallback color
    return "var(--fgColor-black, var(--color-scale-black))" if template.name == "Actions Importer"

    template.lang_color
  end
end
