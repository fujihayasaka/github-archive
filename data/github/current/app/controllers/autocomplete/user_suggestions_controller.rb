# typed: true
# frozen_string_literal: true

class Autocomplete::UserSuggestionsController < ApplicationController
  before_action :login_required
  before_action :require_xhr, only: :index

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    suggester = Suggester::UserSuggester.new(viewer: current_user, cap_filter: cap_filter)
    respond_to do |format|
      format.json do
        render json: suggester.mentions
      end
    end
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
