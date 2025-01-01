# typed: true
# frozen_string_literal: true

module Platform
  # A NullObject representing a resource that is readable by
  # anyone that is part of the Business.
  # This can be passed to control_access when the resource can't define
  # that it is internal by itself.
  class InternalResource
    include Platform::SharedResourceMethods

    delegate :display_login, :flipper_id, :id, :packages, :repositories, :spammy?, to: :resource
    attr_reader :resource
    def initialize(resource: nil)
      @resource = resource
    end

    def readable_by?(actor)
      return false unless @resource

      if @resource.is_a?(Organization)
        readable_by_business_or_resource?(actor)
      else
        resource_readable_by?(actor)
      end
    end

    private

    def readable_by_business_or_resource?(actor)
      business = @resource.business
      business ? business.readable_by?(actor) : @resource.readable_by?(actor)
    end

    def resource_readable_by?(actor)
      @resource.respond_to?(:readable_by?) && @resource.readable_by?(actor)
    end

    def bypass_key
      "cap.internal_resource.bypass"
    end
  end
end
