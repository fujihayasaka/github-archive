# typed: true
# frozen_string_literal: true

class Businesses::People::BulkActionToolbarComponent < ApplicationComponent
  attr_reader :business
  attr_reader :selected_user_ids
  attr_reader :show_remove

  def initialize(business:, selected_user_ids:, show_remove: true)
    @business = business
    @selected_user_ids = selected_user_ids
    @show_remove = show_remove
  end
end
