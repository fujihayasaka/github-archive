# typed: false
# frozen_string_literal: true

module Stratocaster
  module EventTarget
    extend ActiveSupport::Concern

    def events(options = {})
      page = (options[:page] || 1).to_i
      if new_record? || page > 10
        []
      else
        per_page = (options[:per_page] || Stratocaster::DEFAULT_PAGE_SIZE).to_i
        per_page = [per_page, 1].max
        per_page = [per_page, 100].min
        pagination = { page: page, per_page: per_page }
        GitHub.stratocaster.events(events_key(options)).paginate(pagination)
      end
    end

    def events_key(options = {})
      raise NotImplementedError, "See Stratocaster::EventTarget"
    end
  end
end
