# typed: strict
# frozen_string_literal: true

module Actions
  module LargerRunners
    class LargerRunnerDeleteModalComponent < ApplicationComponent
      extend T::Sig

      sig do
        params(
          owner_settings: T.any(EnterpriseRunnersView, OrgRunnersView),
          larger_runner_id: Integer,
          token: T.nilable(String),
          viewing_from_runner_group: T.nilable(T::Boolean)
        ).void
      end
      def initialize(owner_settings:, larger_runner_id:, token: nil, viewing_from_runner_group: false)
        @owner_settings = owner_settings
        @larger_runner_id = larger_runner_id
        @token = token
        @viewing_from_runner_group = viewing_from_runner_group
      end
    end
  end
end
