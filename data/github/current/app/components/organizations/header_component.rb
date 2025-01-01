# typed: true
# frozen_string_literal: true

class Organizations::HeaderComponent < ApplicationComponent
  include ViewModelHelper

  def initialize(organization:, selected_nav_item:)
    @organization = organization
    @selected_nav_item = selected_nav_item
  end

  private

  attr_reader :organization, :selected_nav_item

  # Dummy method definition to satisfy `create_view_model` helper method requirements.
  def user_session
  end
end
