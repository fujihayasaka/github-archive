# typed: true
# frozen_string_literal: true

class Platform::Models::RepositoryInteractionAbility
  attr_reader :interactable

  def initialize(interactable)
    @interactable = interactable
  end

  def interaction_ability
    @interaction_ability ||= ::RepositoryInteractionAbility.new(@interactable)
  end
end
