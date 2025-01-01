# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class TransparencyReport
      include GitHub::Memoizer

      CSV_HEADERS = %w[Field Value].freeze
      private_constant :CSV_HEADERS

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { params(listing: Marketplace::Listing).void }
      def initialize(listing:)
        @listing = listing
      end

      sig { returns(String) }
      def as_csv
        CSV.generate do |csv|
          csv << CSV_HEADERS

          csv_values.each do |row|
            csv << row
          end
        end
      end

      delegate :owner_safe_profile_name, :publisher_2fa_required, :eu_trader, :repository_visibility, :repository_url,
        :third_party_services, :llms_in_use, :is_ai_high_risk, :support_email, :support_url, :privacy_policy_url,
        :tos_url, :status_url, :business_id, :indemnity_status, to: :transparency_data, private: true
      delegate :transparency_disclosure, :name, :copilot_app, :trader_address, :third_party_services,
        to: :listing, private: true

      private

      sig { returns(T::Array[T::Array[String]]) }
      def csv_values
        [
          ["App Name", name],
          ["Listing Type", copilot_app ? "Copilot Extension" : "App"],
          ["Developer", owner_safe_profile_name],
          ["Publisher 2FA Required", publisher_2fa_required],
          ["Company Domain", verified_profile_domains],
          ["Business Address or PO Box", trader_address],
          ["EU Trader", eu_trader],
          ["Required Permissions", required_permissions],
          ["Repository Visibility", repository_visibility],
          ["Repository URL", repository_url],
          ["Third-party Services", third_party_services],
          ["AI Models Used", llms_in_use],
          ["High-risk AI Model", is_ai_high_risk],
          ["Indemnity Status", indemnity_status],
          ["Support Email", support_email],
          ["Support URL", support_url],
          ["Privacy Policy URL", privacy_policy_url],
          ["Terms of Service URL", tos_url],
          ["Status page", status_url],
          ["Business ID", business_id],
          ["Transparency Disclosures", transparency_disclosure],
        ].select { |_, value| value.present? }
      end

      sig { returns(Marketplace::Listings::TransparencyData) }
      memoize def transparency_data
        Marketplace::Listings::TransparencyData.new(listing: listing)
      end

      sig { returns(T.nilable(String)) }
      memoize def verified_profile_domains
        return if (domains = transparency_data.verified_profile_domains).empty?
        domains.join(", ")
      end

      sig { returns(T.nilable(String)) }
      def required_permissions
        return unless (listable = listing.listable).is_a?(Integration)
        latest_version = listable.latest_version

        permissions = latest_version.permissions_of_type(::Repository).merge(
          latest_version.permissions_of_type(Organization)
        ).merge(
          latest_version.permissions_of_type(User)
        )

        permissions.map do |permission, scope|
          next unless scope == :read || scope == :write || scope == :admin
          human_name = Permissions::FineGrainedResources::Metadata.human_name(permission).parameterize.underscore
          "#{scope}:#{human_name}"
        end.join("; ")
      end
    end
  end
end
