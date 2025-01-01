# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listable
    extend ActiveSupport::Concern
    extend T::Sig
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    sig { returns(String) }
    def bgcolor = super

    included do
      T.bind(self, T.class_of(ApplicationRecord::Base))

      # Public: The listing information for the Marketplace, if any.
      # TODO: rename this to something sponsor related?
      has_one :marketplace_listing, class_name: "Marketplace::Listing", as: :listable, dependent: :destroy

      validates :bgcolor, format: { with: /\A([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/ },
                          length: { maximum: 6, minimum: 3 },
                          if: :is_integratable?
    end

    sig { returns(T::Boolean) }
    def is_integratable?
      self.class.name.in?(Marketplace::Listing::INTEGRATABLES)
    end

    # Public: The hash for generating this app's identicon.
    #
    # Returns a 40-character String.
    sig { returns(String) }
    def identicon_hash
      Identicon.hash("#{self.id}#{self.class.name}")
    end

    # Public: The identicon that represents this app.
    #
    # Returns an Identicon.
    sig { returns(Identicon) }
    def identicon
      Identicon.new(identicon_hash)
    end

    # Public: A hex color code for display as the background color for this application's logo.
    #
    # Returns a hex color String without the leading '#'.
    sig { returns(String) }
    def preferred_bgcolor
      async_preferred_bgcolor.sync
    end

    sig { returns(Promise[String]) }
    def async_preferred_bgcolor
      # Always use the background color of the app when synchronized from Dotcom
      if is_integratable? && ProximaAppSynchronization.synchronized?(T.cast(self, Proxima::Syncable))
        return Promise.resolve(self.bgcolor)
      end

      T.unsafe(self).async_marketplace_listing.then do |marketplace_listing|
        next marketplace_listing.bgcolor if marketplace_listing && marketplace_listing.publicly_listed?

        T.unsafe(self).async_primary_avatar.then do |primary_avatar|
          primary_avatar ? self.bgcolor : identicon.background_color
        end
      end
    end
  end
end
