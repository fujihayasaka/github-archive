# typed: true
# frozen_string_literal: true

class FeatureGoneController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  # CAP not required, static page with for 410 error code
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def index
    render file: File.join(Rails.root, "public", "410-feature.html"), status: :gone, layout: false, formats: [:html]
  end
end
