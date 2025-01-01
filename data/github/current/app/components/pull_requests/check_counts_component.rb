# typed: true
# frozen_string_literal: true

class PullRequests::CheckCountsComponent < ApplicationComponent
  include ApplicationComponent::Rescuable

  rescue_from_database_errors with: :nothing

  def initialize(current_repository:, pull_request:, current_tab:)
    @current_repository = current_repository
    @pull_request = pull_request
    @current_tab = current_tab
  end

  def render?
    !current_repository.advisory_workspace?
  end

  private

  attr_reader :current_repository, :pull_request

  def current_tab?
    !!@current_tab
  end
end
