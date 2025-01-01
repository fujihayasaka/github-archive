# typed: true
# frozen_string_literal: true

class Sponsors::FeaturedController < ApplicationController
  before_action :require_xhr, only: :index

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    render Sponsors::Explore::FeaturedAccountsComponent.new, layout: false
  end

  private

  def require_xhr
    head :not_acceptable unless request.xhr? || turbo_frame_request? || current_user&.employee?
  end

  def target_for_conditional_access
    # Featured sponsorables are public and not associated with a possible protected resource.
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
