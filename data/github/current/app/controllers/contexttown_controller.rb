# typed: true
# frozen_string_literal: true

class ContexttownController < ApplicationController
  # CAP not required, employee only and does not return customer-owned resources
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :employee_only, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:index]

  # For debugging GitHub.context
  def index
    render plain: JSON.pretty_generate(GitHub.context.to_hash)
  end
end
