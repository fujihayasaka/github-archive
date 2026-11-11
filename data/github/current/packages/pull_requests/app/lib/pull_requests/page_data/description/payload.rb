# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Description
  class Payload
    class DescriptionPayload < T::Struct
      const :bodyHtml, T.nilable(String), default: nil
    end

    sig do
      params(
        description_data: PullRequests::PageData::Description::Loader::DescriptionData,
      ).returns(DescriptionPayload)
    end
    def self.call(description_data)
      new(
        body_html: description_data.body_html,
      ).call
    end

    sig do
      params(
        body_html: T.nilable(String),
      ).void
    end
    def initialize(
      body_html:
    )
      @body_html = body_html
    end

    sig { returns(DescriptionPayload) }
    def call
      DescriptionPayload.new(
        bodyHtml: @body_html,
      )
    end
  end
end
