# typed: true
# frozen_string_literal: true

# This is configured and ONLY expected to be hit on local development
# via collector.github.localhost!!
class CollectController < ApplicationController

  # Client-side POST doesn't have CSRF token, so conditionally skip that checking
  # Belt and suspenders with the routing which should only ever use this controller in dev.
  skip_before_action :verify_authenticity_token, only: [:create], if: -> { Rails.env.development? }

  def create
    render plain: "", status: :no_content
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end
end
