# typed: true
# frozen_string_literal: true

module Repositories
  class ArchivedNoticeMessageComponent < ApplicationComponent
    def initialize(repository:)
      @repository = repository
    end

    def call
      html_escape(
        if archived_date.present?
          "This repository was archived by the owner on #{archived_date}. It is now read-only."
        else
          "This repository has been archived by the owner. It is now read-only."
        end
      )
    end

    private

    def archived_date
      @repository.archived_at && full_month_date(@repository.archived_at)
    end
  end
end
