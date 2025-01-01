# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module Enablement
      class SettingComponent < ApplicationComponent
        extend T::Sig

        TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        NAME_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        DESCRIPTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        SELECT_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        ENABLE_OPTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        DISABLE_OPTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        BLOCKED_REASON_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        AUX_DATA_TEST_SELECTOR = T.let(SecureRandom.uuid, String)

        class AuxData < T::Struct
          extend T::Sig

          const :name, String
          const :options, T::Array[{ label: String, value: String, description: String }]
          const :initial_value, T.nilable(String)
          const :recommended_value, T.nilable(String)
        end

        class Data < T::Struct
          extend T::Sig

          const :can_enable, T::Boolean, default: true
          const :can_disable, T::Boolean, default: true
          const :description, String
          const :blocked_reason, T.nilable(String)
          const :name, String
          const :render, T::Boolean, default: true
          const :select_name, String
          const :aux_data, T.nilable(AuxData)
        end

        sig { returns(Data) }; attr_reader :data
        sig { returns(T::Boolean) }; attr_reader :straight_bottom_border
        sig { returns(T::Boolean) }; attr_reader :straight_top_border
        sig { returns(T.untyped) }; attr_reader :system_arguments

        sig { params(data: Data, straight_bottom_border: T::Boolean, straight_top_border: T::Boolean, system_arguments: T.untyped).void }
        def initialize(data, straight_bottom_border: false, straight_top_border: false, **system_arguments)
          @data = T.let(data, Data)
          @straight_bottom_border = T.let(straight_bottom_border, T::Boolean)
          @straight_top_border = T.let(straight_top_border, T::Boolean)
          @system_arguments = T.let({ test_selector: TEST_SELECTOR }.merge(system_arguments), T.untyped)
        end

        sig { returns(T::Boolean) }
        def render?
          data.render
        end

        sig { returns(String) }
        def border_box_classes
          classes = []
          classes << "rounded-bottom-0" if straight_bottom_border
          classes << "rounded-top-0" if straight_top_border
          classes.join(" ")
        end

        sig { returns(String) }
        def description_id
          "#{data.select_name.parameterize}-description"
        end

        sig { returns(String) }
        def heading_id
          data.select_name.parameterize
        end

        sig { returns(T::Boolean) }
        def is_blocked?
          !data.can_enable && !data.can_disable
        end

        sig { returns(T::Boolean) }
        def render_aux?
          return false if is_blocked?
          data.aux_data.present?
        end
      end
    end
  end
end
