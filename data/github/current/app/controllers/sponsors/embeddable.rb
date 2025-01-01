# typed: strict
# frozen_string_literal: true

module Sponsors::Embeddable
  extend ActiveSupport::Concern
  extend T::Helpers

  include Sponsors::SharedControllerMethods

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    before_action :sponsorable_required
    before_action :approved_sponsors_listing_required
    before_action :allow_iframe_embedding, only: :show

    private

    sig { void }
    def allow_iframe_embedding
      SecureHeaders.override_x_frame_options(request, "ALLOWALL")
      SecureHeaders.override_content_security_policy_directives(
        request,
        frame_ancestors: [SecureHeaders::PolicyManagement::STAR],
      )
    end

    # Disable user sessions on embeddable pages
    sig { returns T::Boolean }
    def stateless_request?
      true
    end

    sig { returns Symbol }
    def target_for_conditional_access
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end
end
