# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class SweAgentRepositoryAccessFormComponent < ApplicationComponent
      include GitHub::Memoizer

      sig { returns(::Business) }
      attr_reader :configurable

      sig { params(configurable: (::Business)).void }
      def initialize(configurable:)
        @configurable = configurable
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(String) }
      def submit_path
        update_swe_agent_repository_access_enterprise_path(configurable)
      end

      sig { returns(T::Boolean) }
      def checked?
        # The checkbox is labeled as "blocked" so we need to invert the logic here
        !configurable.swe_agent_repository_access_enabled?
      end

      sig { returns(Copilot::Business) }
      memoize def copilot_object
        Copilot::Business.new(configurable)
      end
    end
  end
end
