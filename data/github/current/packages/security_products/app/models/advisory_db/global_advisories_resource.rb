# typed: true
# frozen_string_literal: true

class AdvisoryDB::GlobalAdvisoriesResource
  def initialize(viewer, anonymous_request)
    @viewer = viewer
    @anonymous_request = anonymous_request
  end

  def readable_by?(_)
    true
  end

  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  def async_target_for_conditional_access
    return Promise.resolve(:no_target_for_conditional_access) if @anonymous_request

    @viewer.async_target_for_conditional_access
  end
end
