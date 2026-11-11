# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "github/azure/translator_client"

class DetectCommentLanguageJob < ApplicationJob
  queue_as :detect_comment_language

  retry_on_dirty_exit

  def perform(id, type)
    discussion_or_comment = type.constantize.find_by_id(id)

    return unless translatable_item?(discussion_or_comment)

    language = Localization::AzureTranslations::TranslationService.new.detect_language(discussion_or_comment.body_html)

    with_write do
      discussion_or_comment.update_attribute(:detected_language, language)
    end
  end

  private

  def translatable_item?(item)
    item &&
      item.respond_to?(:body_html) &&
      item.has_attribute?(:detected_language)
  end
end
