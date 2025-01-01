# typed: true
# frozen_string_literal: true

class AppAssociations::BaseController < ApplicationController
  skip_after_action :block_non_xhr_json_responses, only: [:index]
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
end
