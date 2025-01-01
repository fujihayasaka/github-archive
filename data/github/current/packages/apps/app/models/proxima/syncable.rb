# typed: strict
# frozen_string_literal: true

module Proxima
  module Syncable
    extend ActiveSupport::Concern

    included do
      T.bind(self, T.any(T.class_of(Integration), T.class_of(OauthApplication)))

      # Public: Integer state of the application's availability on Proxima
      #
      # column :proxima_availability
      #   :unavailable - Is not available on Proxima
      #   :available - Is available on Proxima
      self.enum :proxima_availability, { unavailable: 0, available: 1 }

      self.scope :syncable_to_proxima, -> { self.where(proxima_availability: 1) }

      self.has_one(:dotcom_app_owner_metadata,
        as: :dotcom_app_owner,
        class_name: "DotcomAppOwnerMetadata",
        dependent: :destroy,
        inverse_of: :local_app,
        foreign_key: :local_app_id,
        foreign_type: :local_app_type
      )
    end

    # Public: Determine if the app is eligible for synchronization to Proxima.
    #
    # Returns a boolean.
    sig { returns(T::Boolean) }
    def syncable_to_proxima?
      syncable_first_party_app? || syncable_third_party_app?
    end

    sig { returns(T::Boolean) }
    def syncable_first_party_app?
      Apps::Privileged.capable?(:proxima_first_party_sync, app: self)
    end

    sig { returns(T::Boolean) }
    def syncable_third_party_app?
      T.bind(self, T.any(Integration, OauthApplication))
      self.available?
    end

    sig { returns(T::Boolean) }
    def synchronized_dotcom_app?
      T.bind(self, T.any(Integration, OauthApplication))

      ProximaAppSynchronization.synchronized?(self)
    end

    sig { returns(T::Boolean) }
    def synchronized_third_party_app?
      T.bind(self, T.any(Integration, OauthApplication))

      ProximaAppSynchronization.synchronized_third_party?(self)
    end

    sig { returns(T.any(User, Organization, Business, NilClass)) }
    def owner
      super
    end
  end
end
