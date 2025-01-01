# typed: true
# frozen_string_literal: true

class TildeRedirectController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  # CAP not required, redirect only
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def index
    safe_redirect_to "/#{path_string}", status: 301
  end
end
