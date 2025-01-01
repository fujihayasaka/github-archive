# typed: strict
# frozen_string_literal: true

module CustomRoles
  class RoleAvatarSpreadComponent < ApplicationComponent
    sig { returns(T::Hash[Symbol, Primer::SystemArgumentsValue]) }
    attr_reader :system_arguments

    renders_many :avatars, ->(actor:, **args) do
      GitHub::AvatarComponent.new(actor:, **args)
    end

    sig { params(system_arguments: Primer::SystemArgumentsValue).void }
    def initialize(**system_arguments)
      @system_arguments = system_arguments
    end

    sig { returns(T::Boolean) }
    def render?
      avatars?
    end

    sig { void }
    def before_render
      avatars.slice!(5..)
    end
  end
end
