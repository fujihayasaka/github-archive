# typed: strict
# frozen_string_literal: true
class MagicShell
  module Strategies
    class AccessibilityLinkUnderlinesEnabled < Base::ViewerContext

      extend T::Sig

      DataType = T.type_alias { T::Boolean }
      DataTypeValue = type_member { { fixed: T.nilable(DataType) } }

      sig { override.returns(T::Types::Base) }
      def self.data_type
        T::Utils.coerce(DataType)
      end

      sig { override.returns(DataTypeValue) }
      def gracefully_degraded_data
        false
      end

      sig { override.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(T::Boolean) }
      def can_use_precomputed_data?(viewer, repository)
        viewer.present?
      end

      sig { override.params(viewer: T.nilable(::User), repository: T.nilable(::Repository)).returns(DataTypeValue) }
      def fetch_live_data(viewer, repository)
        viewer&.settings&.get(:link_underlines)
      end

      sig { override.params(viewer: T.nilable(::User)).returns(DataTypeValue) }
      def precomputed(viewer)
        fetch_live_data(viewer, nil)
      end
    end
  end
end
