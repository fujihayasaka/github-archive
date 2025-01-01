# typed: strict
# frozen_string_literal: true

module Site::FullstoryCaptureDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { ApplicationController }

  include GitHub::Memoizer

  sig { returns(T::Boolean) }
  def fullstory_enabled?
    @fullstory_enabled || false
  end

  private

  sig { void }
  memoize def enable_fullstory
    return if GitHub.single_or_multi_tenant_enterprise?

    @fullstory_enabled = T.let(FeatureFlag.vexi.enabled?(:marketing_fullstory_capture, current_user, default: false) && logged_out?, T.nilable(T::Boolean))
  end

  sig { returns(T::Boolean) }
  def logged_out?
    !logged_in?
  end

  sig { void }
  def add_fullstory_csp_exceptions
    return unless @fullstory_enabled

    csp_exceptions = {
      connect_src: ["edge.fullstory.com", "rs.fullstory.com"],
    }

    SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
  end
end
