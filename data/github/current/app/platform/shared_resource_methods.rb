# typed: true
# frozen_string_literal: true

module Platform
  module SharedResourceMethods
    def readable_by?(_)
      true
    end

    def resource
      @resource
    end

    def resources
      if @resource.respond_to?(:resources)
        @resource.resources
      else
        Kernel.raise Platform::Errors::Internal, "You must implement #resources in your resource class"
      end
    end

    def target_for_conditional_access
      if resource.blank? || !resource.respond_to?(:target_for_conditional_access)
        tags = ["resource:#{resource.class.name}", "async:false"]
        GitHub.dogstats.increment(bypass_key, tags: tags)
        return :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end
      resource.target_for_conditional_access
    end

    def async_target_for_conditional_access
      if resource.blank? || !resource.respond_to?(:async_target_for_conditional_access)
        tags = ["resource:#{resource.class.name}", "async:true"]
        GitHub.dogstats.increment(bypass_key, tags: tags)
        return Promise.resolve(:no_target_for_conditional_access)
      end
      resource.async_target_for_conditional_access
    end

    def bypass_key
      Kernel.raise Platform::Errors::Internal, "You must implement #bypass_key in your resource class"
    end
  end
end
