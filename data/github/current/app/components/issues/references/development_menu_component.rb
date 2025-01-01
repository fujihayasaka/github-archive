# typed: true
# frozen_string_literal: true

# DevelopmentMenuComponent sits in the issue sidebar and allows users to
# link the issue to pull requests and branches from multiple repositories.
# See also: <development-menu>
class Issues::References::DevelopmentMenuComponent < ApplicationComponent
  attr_reader :readonly, :issue

  # issue: Issue
  #   The issue in which the component is rendered
  # readonly: Boolean
  #   True if the issue is locked or the user cannot push to the issue's repository
  def initialize(issue:, readonly:)
    @issue = issue
    @readonly = readonly
  end
end
