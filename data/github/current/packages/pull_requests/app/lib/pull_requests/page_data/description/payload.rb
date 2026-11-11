# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Description
  class Payload
    class DescriptionPayload < T::Struct
      const :body, T.nilable(String), default: nil
      const :bodyHtml, T.nilable(String), default: nil
      const :bodyVersion, T.nilable(String), default: nil
    end

    sig do
      params(
        description_data: PullRequests::PageData::Description::Loader::DescriptionData,
      ).returns(DescriptionPayload)
    end
    def self.call(description_data)
      new(
        body: description_data.body,
        body_html: description_data.body_html,
        body_version: description_data.body_version,
      ).call
    end

    sig do
      params(
        body: T.nilable(String),
        body_html: T.nilable(String),
        body_version: T.nilable(String),
      ).void
    end
    def initialize(
      body:,
      body_html:,
      body_version:
    )
      @body = body
      @body_html = body_html
      @body_version = body_version
    end

    sig { returns(DescriptionPayload) }
    def call
      DescriptionPayload.new(
        body: @body,
        bodyHtml: @body_html,
        bodyVersion: @body_version,
      )
    end
  end
end
