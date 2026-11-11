# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class RepositoryAlertCountComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-risk-repository-alert-count"
      COUNT_TEST_SELECTOR = "security-center-risk-repository-alert-count-counter"

      class Data < T::Struct
        const :alert_count, Integer
        const :feature, String
        const :href, String
        const :repo_id, Integer
        const :repo_locked, T::Boolean, default: false
      end

      sig { returns(Integer) }; attr_reader :alert_count
      sig { returns(String) }; attr_reader :feature
      sig { returns(String) }; attr_reader :href
      sig { returns(Integer) }; attr_reader :repo_id
      sig { returns(T::Boolean) }; attr_reader :repo_locked

      sig { params(data: Data).void }
      def initialize(data)
        @alert_count = T.let(data.alert_count, Integer)
        @feature = T.let(data.feature, String)
        @href = T.let(data.href, String)
        @repo_id = T.let(data.repo_id, Integer)
        @repo_locked = T.let(data.repo_locked, T::Boolean)
      end
    end
  end
end
