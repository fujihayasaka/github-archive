# typed: true
# frozen_string_literal: true

class Autocomplete::EmojisForEditorController < ApplicationController
  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    respond_to do |format|
      format.json do
        render json: GitHub::Emoji.for_editor
      end
    end
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
