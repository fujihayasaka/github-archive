# typed: true
# frozen_string_literal: true

class ComponenttownController < ApplicationController
  # CAP not required, employee only and returns system configuration value
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :employee_only, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    render plain: GitHub.component
  end
end
