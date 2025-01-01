# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class ActionMenuComponent < ApplicationComponent
    extend T::Sig

    class Option < T::Struct
      extend T::Sig

      const :label, String
      const :href, String
      const :selected, T::Boolean

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_action_menu_item_hash
        {
          label: label,
          href: href,
          active: selected
        }
      end
    end

    class Data < T::Struct
      const :options, T::Array[Option]
      const :button_prefix, T.nilable(String)

      def initialize(options:, button_prefix: nil)
        raise ArgumentError, "One option must be selected" unless options.one?(&:selected)
        super(options: options, button_prefix: button_prefix)
      end
    end

    sig { params(data: Data).void }
    def initialize(data:)
      @options = T.let(data.options, T::Array[Option])
      @button_prefix = T.let(data.button_prefix, T.nilable(String))
    end
  end
end
