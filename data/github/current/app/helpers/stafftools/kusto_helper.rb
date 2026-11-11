# typed: true
# frozen_string_literal: true

module Stafftools
  module KustoHelper
    KUSTO_URL = "https://dataexplorer-azure-%{stamp}.githubapp.com"

    # Public: Generates a url to execute a query in kusto
    #
    # Returns a url, or nil for enterprise installations
    sig { params(database: String, query: String).returns(T.nilable(String)) }
    def kusto_query_url(database, query)
      return if GitHub.enterprise?

      encoded_query = URI.encode_www_form_component(query)
      "#{KUSTO_URL % { stamp: "#{GitHub::Config::Proxima.current_stamp_or_dotcom}" }}/databases/#{database}?query=#{encoded_query}"
    end
  end
end
