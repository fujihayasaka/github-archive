# typed: true
# frozen_string_literal: true

class StyleguideController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  stylesheet_bundle :site

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  def index
    redirect_to "https://styleguide.github.com/"
  end
end
