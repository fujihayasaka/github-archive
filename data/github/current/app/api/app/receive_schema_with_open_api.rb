# typed: false
# frozen_string_literal: true

module Api::App::ReceiveSchemaWithOpenApi
  def validate_with_schema(data:, resource:, request:)
    science "rest_api_receive_validation" do |e|
      e.run_if do
        env["openapi.validation_enabled"] == false && @operation.present? && !@operation.ignored?
      end

      e.use { super }

      e.try do
        validate_with_openapi(data: data, operation: @operation, request: request)
      end

      e.compare { |control, candidate| control.valid? == candidate.valid? }
    end
  end
end
