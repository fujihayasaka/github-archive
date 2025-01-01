# typed: strict
# frozen_string_literal: true

class CustomRoles::BannerComponent < ApplicationComponent
  sig { returns(T.untyped) }
  attr_reader :system_arguments

  sig { params(system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(**system_arguments)
    @system_arguments = system_arguments
  end

  sig { returns(T::Boolean) }
  def render?
    flash[:custom_role_banner].present?
  end

  sig { returns(T.nilable(String)) }
  memoize def message
    message_segments = flash[:custom_role_banner]["message_segments"]&.map do |segment|
      next segment unless segment.is_a?(Hash)

      if segment.key?("bold")
        content_tag(:strong, segment["bold"])
      end
    end

    safe_join(message_segments)
  end

  sig { returns(Symbol) }
  def scheme
    flash[:custom_role_banner].fetch("scheme", :default).to_sym
  end

  sig { returns(T.nilable(String)) }
  def assign_role_path
    flash[:custom_role_banner]["assign_role_path"]
  end
end
