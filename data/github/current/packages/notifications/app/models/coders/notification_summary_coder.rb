# typed: true
# frozen_string_literal: true

module Coders
  class NotificationSummaryCoder < Coders::Base
    data_accessors :authors,
                   :items,
                   :title,
                   :creator_id,
                   :issue_state,
                   :issue_number,
                   :number,
                   :milestone_slug,
                   :is_pull_request,
                   :release_tag,
                   :check_suite_conclusion,
                   :is_draft

    def initialize(options = {})
      super options

      data[:authors] ||= {}
      data[:items] ||= {}
      data[:is_pull_request] ||= false
    end

    def is_pull_request
      data[:is_pull_request].to_s.match?(/(1|true)/)
    end
  end
end
