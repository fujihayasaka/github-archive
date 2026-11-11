# typed: strict
# frozen_string_literal: true

# Helper methods for rendering Copilot policy descriptions
module CopilotPoliciesHelper
  # Renders a PolicyDescription array as HTML with proper links
  #
  # description - Array of String and PolicyDescriptionChunk objects
  #
  # Returns a String (HTML safe).
  sig { params(description: Copilot::Policies::PolicyDescription).returns(String) }
  def render_policy_description(description)
    parts = description.map do |part|
      case part
      when Copilot::Policies::PolicyDescriptionChunk
        if part.href
          # Use T.unsafe to access link_to which is available in both helper and component contexts
          T.unsafe(self).link_to(part.text, T.must(part.href), class: "Link--inTextBlock")
        else
          part.text
        end
      when String
        part
      end
    end
    parts.join(" ").html_safe # rubocop:disable Rails/OutputSafety
  end
end
