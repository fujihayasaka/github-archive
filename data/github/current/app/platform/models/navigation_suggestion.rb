# typed: true
# frozen_string_literal: true

# Holds the data required by Platform::Edges::NavigationDestination to represent a
# NavigationDestionation with it's associated metadata
#
# Page key should be "#{type}:#{identifier}" e.g. `repository:github/github`
class Platform::Models::NavigationSuggestion
  attr_accessor :page_key, :destination, :visit_count, :last_visited_at, :generated_at

  def initialize(
    page_key: nil,
    destination: nil,
    visit_count: nil,
    last_visited_at: nil,
    generated_at: nil
  )
    @page_key = page_key
    @destination = destination
    @visit_count = visit_count
    @last_visited_at = last_visited_at
    @generated_at = generated_at
  end
end
