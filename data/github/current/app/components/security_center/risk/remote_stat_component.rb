# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class RemoteStatComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-risk-remote-stat"

      class Data < T::Struct
        const :fragment_src, String
        const :href, T.nilable(String)
        const :title, String
      end

      sig { returns(String) }; attr_reader :fragment_src
      sig { returns(T.nilable(String)) }; attr_reader :href
      sig { returns(String) }; attr_reader :title

      sig { params(data: Data).void }
      def initialize(data)
        @fragment_src = T.let(data.fragment_src, String)
        @href = T.let(data.href, T.nilable(String))
        @title = T.let(data.title, String)
      end
    end
  end
end
