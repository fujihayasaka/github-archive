# typed: true
# frozen_string_literal: true

class Forks::ForksControlsComponentPreview < ViewComponent::Preview
  def default
    render Forks::ForksControlsComponent.new(Forks::PathResolver.new(
      "repo",
      "owner",
      Forks::SearchOptionsResolver.new,
    ))
  end
end
