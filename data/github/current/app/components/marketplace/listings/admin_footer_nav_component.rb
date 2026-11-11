
# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class AdminFooterNavComponent < ApplicationComponent
      include GitHub::Memoizer

      class Step < T::Enum
        enums do
          ContactInfo = new("contact_info")
          ListingDescription = new("listing_description")
          Plans = new("plans")
          Security = new("security")
          Webhook = new("webhook")
          Submit = new("submit")
        end
      end

      sig { params(listing: Marketplace::Listing, current_step_id: Step).void }
      def initialize(listing:, current_step_id:)
        @listing = listing
        @current_step_id = current_step_id
      end

      private


      sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
      memoize def steps
        [
          { id: Step::ContactInfo, title: "Contact info", path: edit_contact_info_marketplace_listing_path(listing.slug) },
          { id: Step::ListingDescription, title: "Listing description", path: edit_description_marketplace_listing_path(listing.slug), next_text: "Fill out your listing description." },
          { id: Step::Plans, title: "Plans and pricing", path: marketplace_listing_plans_path(listing.slug), next_text: "Add plans and pricing." },
          { id: Step::Security, title: "Security and compliance", path: marketplace_listing_security_compliance_path(listing.slug) },
          { id: Step::Webhook, title: "Webhook", path: marketplace_listing_hook_path(listing.slug), next_text: "Add a webhook." },
          { id: Step::Submit, title: "Submit", path: edit_marketplace_listing_path(listing.slug), next_text: "Submit for review!" }
        ].compact
      end

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { returns(Integer) }
      memoize def current_step_idx
        steps.index { |step| step[:id] == @current_step_id } || 0
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def next_step
        steps[current_step_idx + 1]
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def previous_step
        steps[current_step_idx - 1]
      end

      sig { returns(Integer) }
      def num_steps
        # remove one from size so we don't count submit as a step
        steps.size - 1
      end

      sig { returns(Integer) }
      def progress
        ((current_step_idx + 1.0) / num_steps * 100).round
      end
    end
  end
end
