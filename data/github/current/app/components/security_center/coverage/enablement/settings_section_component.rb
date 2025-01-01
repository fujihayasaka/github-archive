# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module Enablement
      class SettingsSectionComponent < ApplicationComponent
        extend T::Sig

        TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        BLOCKED_MESSAGE_TEST_SELECTOR = T.let(SecureRandom.uuid, String)

        class Data < T::Struct
          extend T::Sig

          const :blocked_message, T.nilable(String), default: nil
          const :depth, Integer, default: 1
          const :name, String
          const :render, T::Boolean, default: true
        end

        sig { returns(Data) }; attr_reader :data
        sig { returns(T.untyped) }; attr_reader :system_arguments

        sig { params(data: Data, system_arguments: T.untyped).void }
        def initialize(data, **system_arguments)
          @data = T.let(data, Data)
          @system_arguments = T.let({ test_selector: TEST_SELECTOR }.merge(system_arguments), T.untyped)
        end

        sig { returns(T::Boolean) }
        def render?
          data.render
        end

        sig { returns(Integer) }
        def name_font_size
          data.depth + 2
        end
      end
    end
  end
end
