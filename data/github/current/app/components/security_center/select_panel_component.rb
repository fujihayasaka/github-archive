# typed: strict
# frozen_string_literal: true

require "uri"

module SecurityCenter
  class SelectPanelComponent < ApplicationComponent

    TEST_SELECTOR = "security-center-select-panel"
    DROPDOWN_TEST_SELECTOR = "security-center-select-panel-dropdown"
    ITEM_TEST_SELECTOR = "security-center-select-panel-result"

    class Data < T::Struct
      const :title, String
      const :header, String
      const :options_src, String
    end

    sig { params(data: Data).void }
    def initialize(data)
      @title = T.let(data.title, String)
      @header = T.let(data.header, String)
      @options_src = T.let(data.options_src, String)

      # For the filter in the menu to work,
      # it requires the list rendered and returned by 'src' uses the same ID as the menu plus a suffix.
      # So we need to send the menu ID as part of the request payload.
      @options_src = append_to_query(@options_src, ["menu-id", "security-center-select-panel-#{SecureRandom.uuid}"])
      @options_src = append_to_query(@options_src, ["limit", ::SecurityCenter::Suggestions::Base::MAX_ALLOWED_SUGGESTIONS.to_s])
    end

    private

    sig { params(src: String, param: [String, String]).returns(String) }
    def append_to_query(src, param)
      src_uri = URI::parse(src)
      query_params = URI::decode_www_form(src_uri.query || "") << param
      src_uri.query = URI::encode_www_form(query_params)
      src_uri.to_s
    end
  end
end
