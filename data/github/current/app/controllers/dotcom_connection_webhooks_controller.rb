# typed: true
# frozen_string_literal: true

class DotcomConnectionWebhooksController < ApplicationController
  # CAP bypass okay, only returns static data
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  before_action :require_dotcom_connection_enabled

  def create
    render plain: "OK"
  end
end
