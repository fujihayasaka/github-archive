# typed: true
# frozen_string_literal: true

module IgnoredUsers
  class NoteFieldComponent < ApplicationComponent
    def initialize(current_organization: nil, note: nil, text_field_id:)
      @current_organization = current_organization
      @note = note
      @text_field_id = text_field_id
    end

    private

    def caption
      "Maximum 250 characters. Please don’t include any personal information such as legal names or email addresses. Markdown is supported. #{visibility_scope_notice}"
    end

    def visibility_scope_notice
      if @current_organization.present?
        "All org admins and moderators can see this note."
      else
        "This note will only be visible to you."
      end
    end
  end
end
