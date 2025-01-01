# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::PinnedReposComponent < ApplicationComponent
  include UsersHelper

  def initialize(pinned_repos:)
    @pinned_repos = pinned_repos
  end

  private

  def render?
    @pinned_repos.present?
  end
end
