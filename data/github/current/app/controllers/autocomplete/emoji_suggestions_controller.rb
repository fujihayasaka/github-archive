# typed: true
# frozen_string_literal: true

class Autocomplete::EmojiSuggestionsController < ApplicationController
  before_action :login_required
  before_action :require_xhr, only: :index

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    respond_to do |format|
      format.html do
        render partial: "comments/suggesters/emoji_suggester", locals: {
          emojis: GitHub::Emoji,
          use_colon_emoji: params[:use_colon_emoji].present?,
          tone: logged_in? ? current_user.profile_settings.preferred_emoji_skin_tone : 0,
        }
      end
    end
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
