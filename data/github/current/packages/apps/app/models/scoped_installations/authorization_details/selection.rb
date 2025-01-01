# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    class Selection < T::Enum
      extend T::Sig

      enums do
        None   = new("none")
        Subset = new("subset")
        Parent = new("parent") # Only to be used with a ScopedIntegrationInstallation
        Global = new("global") # Only to be used with a GlobalIntegrationInstallation
        All    = new("all")    # Only to be used with a SiteScopedIntegrationInstallation
      end

      sig { returns(T::Boolean) }
      def none?
        self == None
      end

      sig { returns(T::Boolean) }
      def subset?
        self == Subset
      end

      sig { returns(T::Boolean) }
      def parent?
        self == Parent
      end
    end
  end
end
