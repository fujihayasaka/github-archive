# typed: true
# frozen_string_literal: true

if Rails.env.development? && !ENV["FASTDEV"] && !ENV["PRELOAD"] && !ENV["SKIP_LOOKBOOK"]
  Rails.application.config.to_prepare do
    Lookbook::ApplicationController.class_eval do
      before_action :override_csp_headers

      def override_csp_headers
        SecureHeaders.override_x_frame_options(T.unsafe(self).request, SecureHeaders::XFrameOptions::SAMEORIGIN)
        SecureHeaders.append_content_security_policy_directives(T.unsafe(self).request, {
          script_src: [SecureHeaders::PolicyManagement::UNSAFE_EVAL, SecureHeaders::PolicyManagement::UNSAFE_INLINE],
          frame_src: [SecureHeaders::PolicyManagement::SELF],
          frame_ancestors: [SecureHeaders::PolicyManagement::SELF],
        })
      end

      def logical_service
        "#{GitHub::ServiceMapping::SERVICE_PREFIX}/commands"
      end
    end
  end

  Rails.application.configure do
    T.unsafe(self).config.lookbook.log_use_rails_logger = false
    T.unsafe(self).config.view_component.preview_paths << File.join(Gem::Specification.find_by_name("primer_view_components").gem_dir, "previews")
    T.unsafe(self).config.lookbook.preview_display_options = {
      focusable_siblings: %w[off on]
    }
  end

  Lookbook.add_input_type(:octicon, "lookbook/inputs/octicon")
  Lookbook.add_panel(:accessibility, "lookbook/panels/accessibility", {
    label: "Accessibility",
  })

  ::YARD::Tags::Library.define_tag("Snapshot preview", :snapshot)
end
