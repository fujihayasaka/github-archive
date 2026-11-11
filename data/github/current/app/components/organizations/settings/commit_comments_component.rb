# typed: true
# frozen_string_literal: true

class Organizations::Settings::CommitCommentsComponent < ApplicationComponent
  def initialize(organization:)
    @organization = organization
  end
end
