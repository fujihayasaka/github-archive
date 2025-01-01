# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator
  module NotificationType
    # Common reason groups
    MUTED = { name: "notify_muted", reasons: %w[mention team_mention] }
    PARTICIPANT = { name: "participant", reasons: %w[author comment assign state_change mention team_mention manual] }

    module IType
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
      def config; end

      sig { abstract.returns(T::Hash[Symbol, T::Boolean]) }
      def feature_switches; end
    end

    class Standard
      extend T::Sig
      include IType

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def config
        {
          reason_groups: [
            MUTED,
            PARTICIPANT,
          ]
        }
      end

      sig { override.returns(T::Hash[Symbol, T::Boolean]) }
      def feature_switches
        {}
      end
    end

    class OptOut
      extend T::Sig
      include IType

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def config
        {
          reason_groups: [
            MUTED,
            PARTICIPANT,
          ]
        }
      end

      sig { override.returns(T::Hash[Symbol, T::Boolean]) }
      def feature_switches
        {
          notify_actor: true,
          notify_subscribers: false
        }
      end
    end
  end
end
