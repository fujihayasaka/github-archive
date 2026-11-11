# typed: true
# frozen_string_literal: true

module Discussions
  class ReferenceInNewIssueForm < ApplicationForm
    form do |new_issue_form|
      new_issue_form.text_field(
        name: "issue[title]",
        label: "Issue title",
        required: true,
        full_width: true,
        value: @title,
      )

      new_issue_form.text_area(
        name: "issue[body]",
        label: "Issue body",
        required: true,
        rows: 9,
        value: @body,
        data: @view_context.current_user&.paste_url_link_as_plain_text? ? { paste_url_links_as_plain_text: "" } : {}
      )

      new_issue_form.group(layout: :horizontal) do |button_group|
        button_group.button(name: :button, label: "Cancel", data: { close_dialog_id: @dialog_close_id })
        button_group.submit(name: :submit, scheme: :primary, label: "Create issue")
      end
    end

    def initialize(title:, body:, dialog_close_id:)
      @title = title
      @body = body
      @dialog_close_id = dialog_close_id
    end
  end
end
