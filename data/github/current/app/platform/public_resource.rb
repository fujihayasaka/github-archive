# typed: true
# frozen_string_literal: true

module Platform
  # A NullObject representing a resource that is readable by
  # anyone under any circumstances.
  # This can be passed to control_access when no other handy
  # object is available.
  class PublicResource

    attr_reader :resource
    def initialize(resource: nil)
      @resource = resource
    end

    def readable_by?(_)
      true
    end

    def target_for_conditional_access
      if resource.blank? || !resource.respond_to?(:target_for_conditional_access)
        tags = ["resource:#{resource.class.name}", "async:false"]
        GitHub.dogstats.increment("cap.public_resource.bypass", tags: tags)
        # PublicResource may have a target_for_conditional_access (owner)
        # depending on its usage, but this preserves the existing behavior of
        # CAP enforcement being bypassed when this is used for API CAP authz
        return :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end

      resource.target_for_conditional_access
    end

    def async_target_for_conditional_access
      if resource.blank? || !resource.respond_to?(:async_target_for_conditional_access)
        tags = ["resource:#{resource.class.name}", "async:true"]
        GitHub.dogstats.increment("cap.public_resource.bypass", tags: tags)
        return Promise.resolve(:no_target_for_conditional_access)
      end

      resource.async_target_for_conditional_access
    end
  end
end
