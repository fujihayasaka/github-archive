# typed: true
# frozen_string_literal: true

module Platform
  # A NullObject representing a resource that is readable by
  # anyone under any circumstances.
  # This can be passed to control_access when no other handy
  # object is available.
  class PublicResource
    include Platform::SharedResourceMethods

    attr_reader :resource
    def initialize(resource: nil)
      @resource = resource
    end

    private

    def bypass_key
      "cap.public_resource.bypass"
    end
  end
end
