# frozen_string_literal: true

module HasSearching
  def hidden_search_fields
    request.query_parameters.except("query", "page")
  end
end
