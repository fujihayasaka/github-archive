# typed: true
# frozen_string_literal: true

class DiscussionTimeline::BodyRenderer
  sig { params(records: T.untyped, context: T.untyped).void }
  def initialize(records, context:)
    @records = records
    @cache_context = context
  end

  sig { returns(T.untyped) }
  def async_body_html_by_record
    promises = records.map { |record| record.async_body_html(context: @cache_context) }

    Promise.all(promises).then do |body_htmls|
      records.zip(body_htmls).to_h
    end
  end

  private

  attr_reader :records
end
