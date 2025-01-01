# typed: true
# frozen_string_literal: true

# Used to signal a resource that can't or shouldn't be
# enforced in terms of Conditional Access
#
# This class is of internal use for CAP Framework, and
# not to be used in any application logic other than
# the foundations of our API CAP enforcement.
module ConditionalAccess
  class UnenforceableResource
    def self.instance
      @instance ||= UnenforceableResource.new
    end

    def target_for_conditional_access
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    def async_target_for_conditional_access
      Promise.resolve(:no_target_for_conditional_access)
    end
  end
end
