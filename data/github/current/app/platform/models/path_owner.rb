# typed: true
# frozen_string_literal: true

class Platform::Models::PathOwner
  include ActionView::Helpers::TagHelper

  # name  - A name string that will equal :login for User/Organization or :name for Team.
  #         These are the owners for a specified file path in the CODEOWNERS file.
  def initialize(name:)
    @name = name
  end

  attr_reader :name
end
