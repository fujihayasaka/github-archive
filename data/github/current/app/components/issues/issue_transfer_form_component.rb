# typed: true
# frozen_string_literal: true

module Issues
  class IssueTransferFormComponent < ApplicationComponent
    attr_reader :issue
    attr_reader :form_path

    def initialize(issue:, form_path:)
      @issue = issue
      @form_path = form_path
    end
  end
end
