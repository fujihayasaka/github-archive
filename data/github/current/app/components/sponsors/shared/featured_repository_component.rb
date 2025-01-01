# typed: strict
# frozen_string_literal: true

class Sponsors::Shared::FeaturedRepositoryComponent < ApplicationComponent
  sig { params(repo: Repository).void }
  def initialize(repo:)
    @repo = repo
  end

  private

  sig { returns T::Boolean }
  def render?
    @repo.public?
  end
end
