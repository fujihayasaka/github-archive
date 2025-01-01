# typed: true
# frozen_string_literal: true

module Stafftools
  module Zendesk
    URL = "https://github.zendesk.com/agent/search/1?q="
    # Generates a Zendesk search link for a specific email address or username.
    #
    # element - the email/username to search for.
    def zendesk_search_url(element)
      URL + element
    end
  end
end
