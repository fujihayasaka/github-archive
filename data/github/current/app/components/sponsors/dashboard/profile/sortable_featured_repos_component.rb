# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::SortableFeaturedReposComponent < ApplicationComponent
  def initialize(featured_repos:)
    @featured_repos = featured_repos
  end

  private

  attr_reader :featured_repos
end
