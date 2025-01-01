# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Simple filter to work around the fact that Nokogiri
  # seems to add a rogue newline so our "fixed" whitespace
  # display of email replies is causing an extra newline to
  # be erroneously displayed before some messages.
  class LeadingNewlineFilter < Filter
    def call
      html.sub "class=\"email-fragment\">\n", "class=\"email-fragment\">"
    end
  end
end
