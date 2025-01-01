# typed: strict
# frozen_string_literal: true

class ContentfulCustomContent
  # Initializes a new ContentfulCustomContent instance.
  #
  # @param contentful_payload [Hash] The payload received from Contentful API
  # @param custom_page_param [String] The get-started-with query parameter that identifies which custom page content to display
  sig { params(contentful_payload: T.nilable(T::Hash[String, T.untyped]), custom_page_param: String).void }
  def initialize(contentful_payload, custom_page_param)
    @contentful_payload = contentful_payload
    @custom_page_param = custom_page_param
  end

  # Parses through the Contentful payload and returns only what we need to render a single custom content page.
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def to_h
    return nil if contentful_payload.nil? || entries.empty? || page_entry.nil?

    ({
      entry: page_entry,
      content_entries: content_entries,
      assets: asset_entries
    }).deep_symbolize_keys
  end

  private

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  attr_reader :contentful_payload

  sig { returns(String) }
  attr_reader :custom_page_param

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def entries
    @entries ||= T.let(
      contentful_payload&.dig("includes", "Entry") || [],
      T.nilable(T::Array[T::Hash[String, T.untyped]]),
    )
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def assets
    @assets ||= T.let(
      contentful_payload&.dig("includes", "Asset") || [],
      T.nilable(T::Array[T::Hash[String, T.untyped]]),
    )
  end

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def page_entry
    @page_entry ||= T.let(
      entries.find { |e| e.dig("fields", "htmlId")&.downcase == custom_page_param.downcase },
      T.nilable(T::Hash[String, T.untyped]),
    )
  end

  sig { returns(T::Array[String]) }
  def page_entry_content_ids
    Array(page_entry&.dig("fields", "content")).map { |c| c.dig("sys", "id") }
  end

  sig { returns(T::Array[String]) }
  def page_entry_asset_ids
    Array(page_entry&.dig("fields", "media")).map { |c| c.dig("sys", "id") }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def entries_by_id
    @entries_by_id ||= T.let(entries.index_by { |e| e.dig("sys", "id") }, T.nilable(T::Hash[String, T.untyped]))
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def content_entries
    page_entry_content_ids.filter_map { |id| entries_by_id[id] }
  end

  sig { returns(T::Array[T::Hash[String, String]]) }
  def asset_entries
    asset_by_id = assets.index_by { |e| e.dig("sys", "id") }
    asset_entry_ids = page_entry_asset_ids.filter_map do |id|
      asset_id = entries_by_id[id]&.dig("fields", "asset", "sys", "id")
      html_id = entries_by_id[id]&.dig("fields", "id")
      { asset_id: asset_id, html_id: html_id } if asset_id && html_id
    end

    asset_entry_ids.filter_map do |entry|
      asset = asset_by_id[entry[:asset_id]]
      next if asset.nil?

      url = asset.dig("fields", "file", "url")
      next if url.nil?

      url = "https:#{url}"

      alt_text = asset.dig("fields", "description")
      {
        "html_id" => entry[:html_id],
        "url" => url,
        "alt_text" => alt_text
      }
    end
  end
end
