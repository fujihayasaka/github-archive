# typed: true
# frozen_string_literal: true

module Api::Serializer::GraphqlHelperDependency
  MimeBodyFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Comment {
      body @include(if: $includeBody)
      bodyHTML @include(if: $includeBodyHTML)
      bodyText @include(if: $includeBodyText)
    }
  GRAPHQL

  # Handle various body formats for Accept mime types
  #
  # record - a hash that contains keys "body", "body_html", and "body_text"
  # options - Hash
  def graphql_mime_body_hash(record, options)
    record = MimeBodyFragment.new(record)
    return unless record

    params   = options[:mime_params] || []
    full     = params.include? :full
    any_body = false
    hash     = {}
    if full || params.include?(:html)
      any_body = true
      hash.update body_html: record.body_html.presence
    end
    if full || params.include?(:text)
      any_body = true
      hash.update body_text: record.body_text.presence
    end
    if full || !any_body || params.include?(:raw)
      hash.update body: record.body.presence
    end

    hash
  end
end
