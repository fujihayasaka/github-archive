# typed: true
# frozen_string_literal: true

# The internal scanner only returns results for Urls within the github.com domain.
class OpenGraph::Internal::Scanner < OpenGraph::Scanner
  def scan
    if external_url?(url)
      return ::OpenGraph::Scanner::Result.new
    end

    super
  end
end
