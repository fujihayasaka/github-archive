# typed: true
# frozen_string_literal: true

class ComponentPreviewsController < ApplicationController
  include ViewComponent::PreviewActions

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
