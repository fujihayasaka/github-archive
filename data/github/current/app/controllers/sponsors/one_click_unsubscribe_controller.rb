# typed: strict
# frozen_string_literal: true

# Endpoint supporting RFC 8058 one-click email unsubscribe
class Sponsors::OneClickUnsubscribeController < ApplicationController
  # No CSRF token for the POST request since it's sent by email clients
  skip_before_action :verify_authenticity_token, only: [:create]

  sig { void }
  def create
    token = params[:token]
    Sponsors::OneClickUnsubscribe.process_token(token)
    head :ok
  end

  private

  sig { returns Symbol }
  def target_for_conditional_access
    # This POST request must be handled w/o any redirects per RFC 8058
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
