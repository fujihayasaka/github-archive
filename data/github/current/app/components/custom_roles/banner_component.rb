# typed: strict
# frozen_string_literal: true

class CustomRoles::BannerComponent < ApplicationComponent
  sig { returns(T.nilable(T::Hash[T.any(Symbol, String), T.untyped])) }
  attr_reader :banner_flash
  sig { returns(T.untyped) }
  attr_reader :system_arguments

  sig { params(banner_flash: T.nilable(T::Hash[T.any(Symbol, String), T.untyped]), system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(banner_flash, **system_arguments)
    @banner_flash = banner_flash
    @system_arguments = system_arguments
  end

  sig { returns(T::Boolean) }
  def render?
    banner_flash.present?
  end

  sig { returns(T.nilable(String)) }
  memoize def message
    message_segments = T.must(banner_flash)["message_segments"]&.map do |segment|
      next segment unless segment.is_a?(Hash)

      if segment.key?(:bold)
        content_tag(:strong, segment[:bold])
      end
    end

    safe_join(message_segments)
  end

  sig { returns(Symbol) }
  def scheme
    T.must(banner_flash).fetch("scheme", :default).to_sym
  end

  sig { returns(T.nilable(String)) }
  def assign_role_path
    T.must(banner_flash)["assign_role_path"]
  end
end
