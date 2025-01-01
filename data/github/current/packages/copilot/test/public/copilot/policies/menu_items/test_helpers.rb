# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module TestHelpers
        extend T::Helpers
        abstract!

        sig do
          params(public_code_suggestions: Symbol,
                 chat_enabled: Symbol,
                 dotcom_chat: Symbol,
                 cli: Symbol,
                 mobile_chat: Symbol,
                 copilot_extensions: Symbol,
                 private_telemetry: Symbol,
                 usage_telemetry_api: Symbol,
                 a_chat: Symbol,
                 g_chat: Symbol,
                 o1: Symbol).returns(Copilot::Organization)
        end
        def organization(public_code_suggestions: :allowed,
                         chat_enabled: :enabled,
                         dotcom_chat: :enabled,
                         cli: :enabled,
                         mobile_chat: :enabled,
                         copilot_extensions: :enabled,
                         private_telemetry: :enabled,
                         usage_telemetry_api: :enabled,
                         a_chat: :enabled,
                         g_chat: :enabled,
                         o1: :enabled)
          org = FactoryBot.create(:organization)
          FactoryBot.create(:copilot_configuration, :organization,
                            configurable: org,
                            public_code_suggestions: public_code_suggestions,
                            chat_enabled: chat_enabled,
                            dotcom_chat: dotcom_chat,
                            cli: cli,
                            mobile_chat: mobile_chat,
                            copilot_extensions: copilot_extensions,
                            private_telemetry: private_telemetry,
                            usage_telemetry_api: usage_telemetry_api,
                            a_chat: a_chat,
                            g_chat: g_chat,
                            o1: o1)
          Copilot::Organization.new(org)
        end

        sig do
          params(
            public_code_suggestions: Symbol,
                 chat_enabled: Symbol,
                 dotcom_chat: Symbol,
                 cli: Symbol,
                 mobile_chat: Symbol,
                 copilot_extensions: Symbol,
                 private_telemetry: Symbol,
                 usage_telemetry_api: Symbol,
                 a_chat: Symbol,
                 g_chat: Symbol,
                 o1: Symbol).returns(Copilot::Business)
        end
        def business(public_code_suggestions: :allowed,
                     chat_enabled: :enabled,
                     dotcom_chat: :enabled,
                     cli: :enabled,
                     mobile_chat: :enabled,
                     copilot_extensions: :enabled,
                     private_telemetry: :enabled,
                     usage_telemetry_api: :enabled,
                     a_chat: :enabled,
                     g_chat: :enabled,
                     o1: :enabled)
          biz = FactoryBot.create(:business)
          FactoryBot.create(:copilot_configuration, :business,
                            configurable: biz,
                            public_code_suggestions: public_code_suggestions,
                            chat_enabled: chat_enabled,
                            dotcom_chat: dotcom_chat,
                            cli: cli,
                            mobile_chat: mobile_chat,
                            copilot_extensions: copilot_extensions,
                            private_telemetry: private_telemetry,
                            usage_telemetry_api: usage_telemetry_api,
                            a_chat: a_chat,
                            g_chat: g_chat,
                            o1: o1)
          Copilot::Business.new(biz)
        end

        sig { params(checked: T::Boolean, description: String, name: String, type: String).void }
        def expect_component_attrs(checked:, description:, name:, type: "submit")
          class_name = T.must(T.cast(self, GitHub::TestCase).class.name).gsub("Test", "")
          GitHub::Menu::ButtonComponent.expects(:new).with(
            text: class_name.demodulize.titleize.humanize,
            replace_text: class_name.demodulize.titleize.humanize,
            checked: checked,
            description: description,
            name: name,
            value: class_name.demodulize.underscore,
            type: type,
          ).once
        end

        sig do
          params(checked: T::Boolean, description: String)
            .returns({
              id: String,
              selected: T::Boolean,
              title: String,
              description: String,
              value: String
            })
        end
        def expected_hash(checked:, description:)
          class_name = T.must(T.cast(self, GitHub::TestCase).class.name).gsub("Test", "")
          {
            id: class_name,
            selected: checked,
            title: class_name.demodulize.titleize.humanize,
            description: description,
            value: class_name.demodulize.underscore
          }
        end
      end
    end
  end
end
