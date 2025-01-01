# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      class Base
        extend T::Sig
        extend T::Helpers
        abstract!

        sig { returns(T.any(Copilot::User, Copilot::Organization, Copilot::Business)) }
        attr_reader :copilot_configurable

        sig { returns(String) }
        attr_reader :type

        sig { params(copilot_configurable: T.any(Copilot::User, Copilot::Organization, Copilot::Business), type: String, checked: T.nilable(T::Boolean)).void }
        def initialize(copilot_configurable:, type: "submit", checked: nil)
          @copilot_configurable = copilot_configurable
          @type = type
          @checked = checked
        end

        sig { returns(T.nilable(GitHub::Menu::ButtonComponent)) }
        def component
          return unless render?

          GitHub::Menu::ButtonComponent.new(
            text: text,
            replace_text: text,
            checked: checked?,
            description: description,
            name: name,
            value: value,
            type: type,
          )
        end

        sig { returns(T.nilable(Copilot::Types::MenuItemHashType)) }
        def to_h
          return unless render?

          {
            id: self.class.name.to_s,
            selected: checked?,
            title: text,
            description: description,
            value: value
          }
        end

        private

        sig { abstract.returns(String) }
        def name; end

        sig { abstract.returns(T::Boolean) }
        def checked?; end

        sig { returns(String) }
        def text
          T.must(self.class.name).demodulize.titleize.humanize
        end

        sig { returns(String) }
        def description
          ""
        end

        sig { returns(T::Boolean) }
        def render?
          true
        end

        sig { returns(String) }
        def value
          text.parameterize.underscore
        end

        sig { returns(T::Boolean) }
        def business?
          copilot_configurable.__getobj__.is_a?(::Business)
        end

        sig { returns(T::Boolean) }
        def standalone_business?
          return false unless business?
          T.cast(copilot_configurable, Copilot::Business).copilot_standalone?
        end

        sig { returns(T::Boolean) }
        def user?
          copilot_configurable.__getobj__.is_a?(::User)
        end

        sig { returns(T::Boolean) }
        def organization?
          copilot_configurable.__getobj__.is_a?(::Organization)
        end
      end
    end
  end
end
