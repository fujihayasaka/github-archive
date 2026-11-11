# typed: true
# frozen_string_literal: true

class GitignoreController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests

  # The following actions do not require conditional access checks:
  # - show: serves `/site/gitignore/:template`, a simple endpoint to
  #   look up and render .gitignore templates, with no access to protected
  #   organization resources.
  # - list: serves `/site/gitignore/templates`, returns a list of available gitignore templates
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: [:show, :index]
  # rubocop:enable GitHub/DoNotSkipCapBeforeAction

  def index
    render json: Gitignore.templates
  end

  def show
    template = params[:template]
    render plain: Gitignore.template(template)
  end
end
