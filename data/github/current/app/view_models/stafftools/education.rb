# typed: true
# frozen_string_literal: true

module Stafftools
  module Education
    # Generates a Education Web search link for a user_id.
    #
    # user_id - the user id to search for
    def education_search_url(user_id)
      "https://education.github.com/stafftools/search?q=#{user_id}"
    end
  end
end
