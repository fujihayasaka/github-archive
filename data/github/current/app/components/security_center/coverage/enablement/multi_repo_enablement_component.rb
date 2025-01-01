# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module Enablement
      class MultiRepoEnablementComponent < ApplicationComponent
        extend T::Sig

        TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        FORM_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        SHOW_BUTTON_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        SUBMIT_BUTTON_TEST_SELECTOR = T.let(SecureRandom.uuid, String)

        TURBO_FRAME_ID = MultiRepoEnablementContentComponent::TURBO_FRAME_ID

        class Data < T::Struct
          const :content_url, String
          const :form_url, String
          const :query, String, default: ""
        end

        sig { returns(Data) }; attr_reader :data
        sig { returns(T.untyped) }; attr_reader :system_arguments

        sig { params(data: Data, system_arguments: T.untyped).void }
        def initialize(data, **system_arguments)
          @data = T.let(data, Data)
          @system_arguments = T.let({ test_selector: TEST_SELECTOR }.merge(system_arguments), T.untyped)
        end
      end
    end
  end
end
