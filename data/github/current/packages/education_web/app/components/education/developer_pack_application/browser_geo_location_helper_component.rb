# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class BrowserGeoLocationHelperComponent < ApplicationComponent
      PARTIAL_NAME = T.let("browser-geo-location".freeze, String)

      sig do
        params(
          location_shared_input_id: String,
          latitude_input_id: String,
          longitude_input_id: String,
        ).void
      end
      def initialize(location_shared_input_id:, latitude_input_id:, longitude_input_id:)
        @location_shared_input_id = location_shared_input_id
        @latitude_input_id = latitude_input_id
        @longitude_input_id = longitude_input_id
      end

      sig { returns(String) }
      def call
        content_tag(
          :div,
          render_react_partial(
            name: PARTIAL_NAME,
            props: {
              locationSharedInputId: @location_shared_input_id,
              latitudeInputId: @latitude_input_id,
              longitudeInputId: @longitude_input_id,
            },
          ),
          data: {
            test_selector: "browser-geo-location-helper-react-partial",
          },
        )
      end
    end
  end
end
