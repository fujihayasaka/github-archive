# typed: true
# frozen_string_literal: true

module UserLists
  class CreateDialogComponent < ApplicationComponent
    renders_one :summary

    # repository_id - Optional ID of a Repository. If included, the generated form will include a hidden input, and
    #   when submitted the specified repository will be added to the created list.
    # details_classes - String containing CSS classes to append to the <details> element in the dialog.
    def initialize(repository_id: nil, details_classes: nil)
      @repository_id = repository_id
      @details_classes = class_names("js-follow-list", details_classes)
    end

    private

    attr_reader :repository_id, :details_classes
  end
end
