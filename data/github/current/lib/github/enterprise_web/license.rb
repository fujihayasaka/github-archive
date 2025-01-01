# typed: true
# frozen_string_literal: true

module GitHub
  module EnterpriseWeb
    class License
      UNLIMITED_TYPE = "unlimited"
      EVALUATION_TYPE = "evaluation"

      STANDARD_INSTANCE_TYPE = "standard"

      attr_reader :id, :created_at, :updated_at, :starts_at, :expires_at, :seats,
        :learning_lab_seats, :checksum, :learning_lab_evaluation_expires_at,
        :type, :state, :advanced_security_enabled, :advanced_security_seats, :instance_type

      # Returns all valid licenses for a given enterprise web business.
      # This will raise if the API request fails.
      #
      # Returns an array of GitHub::EnterpriseWeb::License
      def self.all(enterprise_web_business_id)
        response = Client.get("/api/businesses/#{enterprise_web_business_id}/licenses")
        response.body[:data].map { |json| new(json) }
      end

      # Returns the license data for a given business and license reference ID
      #
      # Returns a String
      def self.download(enterprise_web_business_id, reference_id)
        response = Client.get("/api/businesses/#{enterprise_web_business_id}/licenses/#{reference_id}/download")
        response.body
      end

      def initialize(json)
        @id = json[:id]
        @created_at = parse_date(json[:attributes][:created_at])
        @updated_at = parse_date(json[:attributes][:updated_at])
        @starts_at = parse_date(json[:attributes][:starts_at])
        @expires_at = parse_date(json[:attributes][:expires_at])
        @seats = json[:attributes][:seats]
        @learning_lab_seats = json[:attributes][:learning_lab_seats]
        @checksum = json[:attributes][:checksum]
        @learning_lab_evaluation_expires_at = json[:attributes][:learning_lab_evaluation_expires_at]
        @type = json[:attributes][:type]
        @state = json[:attributes][:state]
        @advanced_security_enabled = json[:attributes][:advanced_security_enabled]
        @advanced_security_seats = json[:attributes][:advanced_security_seats]
        @instance_type = json[:attributes][:instance_type]

        freeze
      end

      def unlimited?
        type == UNLIMITED_TYPE || type == EVALUATION_TYPE
      end

      def advanced_security_enabled?
        advanced_security_enabled
      end

      def downloadable?
        instance_type == STANDARD_INSTANCE_TYPE
      end

      private

      def parse_date(value)
        if value.present?
          Date.parse(value)
        end
      end
    end
  end
end
