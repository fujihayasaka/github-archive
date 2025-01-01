# typed: true
# frozen_string_literal: true

class Localization::TranslationsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :require_translatable

  TRANSLATABLE_TYPES = {
    discussion: Discussion,
    comment: DiscussionComment
  }

  rescue_from Localization::AzureTranslations::TranslationService::HttpError do |error|
    render json: { error: error.message }, status: error.http_status
  end

  rescue_from Localization::AzureTranslations::HtmlSplitter::SplitError do |error|
    render json: { error: error.message }, status: 400
  end

  def create
    text = translatable_as_html
    translation = translations.translate(text, to: params[:to], from: params[:from])
    json = [{ translations: [{ text: translation, to: params[:to] }] }]

    render json: json
  end

  private

  memoize def translations
    translations = Localization::AzureTranslations::TranslationService.new
  end

  memoize def translatable
    type = params[:type].to_sym
    return head :bad_request unless TRANSLATABLE_TYPES.key?(type)

    klass = TRANSLATABLE_TYPES[type]
    translatable = klass.find(params[:id].to_i)

    return false unless translatable.readable_by?(current_user)

    translatable
  end

  def require_translatable
    render_404 unless translatable
  end

  def translatable_as_html
    if translatable.is_a?(Discussion) || translatable.is_a?(DiscussionComment)
      discussion_or_comment = translatable

      # This uses a partial as a workaround until https://github.com/rails/rails/pull/45432 is merged
      # Right now, using the view component directly does not work with passing a block for slots.
      render_to_string partial: "localization/translations/discussion_comment",
        locals: { discussion_or_comment: discussion_or_comment },
        formats: :html,
        layout: false
    end
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
