# typed: true
# frozen_string_literal: true

module Gists
  # Controls the gist new/create view
  # eg https://github.com/gists/
  class EditPageView < NewPageView

    attr_reader :gist

    delegate :owner, :description, :visibility, :files_for_view, :user_param, to: :gist

    def page_title
      "Editing #{gist.title}"
    end

    # What objects does the form_for tag operate on?
    def form_objects
      [owner, gist]
    end
  end
end
