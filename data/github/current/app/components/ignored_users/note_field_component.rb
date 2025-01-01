# typed: true
# frozen_string_literal: true

module IgnoredUsers
  class NoteFieldComponent < ApplicationComponent
    AVOID_PII_NOTICE = "Please don't include any personal information such as legal names or "\
      "email addresses."
    VISIBILITY_SCOPE_NOTICE = "This note will be visible to %{visibility_scope}."

    def initialize(current_organization: nil, note: nil, visually_hide_label: true, text_field_id:)
      @current_organization = current_organization
      @note = note
      @visually_hide_label = visually_hide_label
      @text_field_id = text_field_id
    end

    private

    def visibility_scope
      if @current_organization.present?
        "other owners and moderators of the #{current_organization.safe_profile_name} organization"
      else
        "only you"
      end
    end
  end
end
