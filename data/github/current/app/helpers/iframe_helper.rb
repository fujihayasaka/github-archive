# typed: true
# frozen_string_literal: true

module IframeHelper
  # Providing a separate function to allow for calling this when loading parent and child page within the application.
  # call this function with caution and review in #prodsec-engineering to ensure safe use of this method.
  # values must be in-line with values for CSP headers: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy and https://csp.withgoogle.com/docs/index.html
  def self.override_iframe_http_headers(request, x_frame_options: "", frame_ancestors: "", object_src: "")
    if self.valid_policy_change(object_src)
      SecureHeaders::override_content_security_policy_directives(request, { object_src: ["'#{object_src}'"] })
    end
    if self.valid_policy_change(frame_ancestors)
      SecureHeaders::override_content_security_policy_directives(request, { frame_ancestors: ["'#{frame_ancestors}'"] })
    end
    if self.valid_policy_change(x_frame_options)
      SecureHeaders::override_x_frame_options(request, x_frame_options)
    end
  end

  # Called to enable iframe embedding for a specific page.
  # Double check the object_src is used appropriately
  def self.allow_iframe(request)

    # CSP Exception for HTML content
    csp_exceptions = {
        frame_src: [SecureHeaders::PolicyManagement::SELF]
    }

    SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
  end

  # Called on pages being displayed within iframes.
  def self.allow_iframe_embedding(request, pdf: false)

    # CSP Exception for HTML content
    csp_exceptions = {
        frame_ancestors: [SecureHeaders::PolicyManagement::SELF]
    }

    # CSP Exception for PDF content
    if pdf
      csp_exceptions[:object_src] = [SecureHeaders::PolicyManagement::SELF]
    end

    SecureHeaders.override_content_security_policy_directives(request, csp_exceptions)
    SecureHeaders.override_x_frame_options(request, SecureHeaders::XFrameOptions::SAMEORIGIN)
  end

  private_class_method def self.valid_policy_change(subject)
    subject.length > 0
  end
end
