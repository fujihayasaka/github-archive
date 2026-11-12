# frozen_string_literal: true

require "erb"

class Renderer
  class << self
    def render_error(status:, title:, detail: nil)
      error = { status: status, title: title }
      error[:detail] = detail if detail.present?

      render({ errors: [error] }.to_json, status: status)
    end

    def resource(resource, status: 200, serializer_options: {})
      serializable_resource = ActiveModelSerializers::SerializableResource.new(
        resource,
        serializer_options,
      )

      render(serializable_resource.to_json, status: status)
    end

    def resources(resources, request:, status: 200, serializer_options: {})
      serialization_context =
        ActiveModelSerializers::SerializationContext.new(request)

      serializer_options[:serialization_context] = serialization_context

      serializable_resource =
        ActiveModelSerializers::SerializableResource.new(
          resources,
          serializer_options,
        )

      render(serializable_resource.to_json, status: status)
    end

    def no_content
      render(nil, status: 204)
    end

    def render(json_body, status: 200)
      body = json_body.present? ? [json_body] : []
      [status, { "content-type" => "application/json" }, body]
    end
  end
end
