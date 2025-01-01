# typed: true
# frozen_string_literal: true

class Force502Controller < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  # CAP not required, this controller returns static data
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def index
    render plain: "I am a 502", status: 502
  end
end
