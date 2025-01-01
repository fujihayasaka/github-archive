# typed: strict
# frozen_string_literal: true

require "uri"

module SecurityCenter
  module Coverage
    class SelectMenuComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-coverage-select-menu"

      class Filter < T::Struct
        const :placeholder, String
      end

      class ClearOption < T::Struct
        const :text, String
        const :href, String
      end

      class Data < T::Struct
        const :name, String
        const :header, String
        const :icon, T.nilable(String)
        const :filter, T.nilable(Filter)
        const :options, T.nilable(T::Array[SelectMenu::ListComponent::OptionData])
        const :options_src, T.nilable(String)
        const :clear_option, T.nilable(ClearOption)

        def initialize(name:, header:, icon: nil, filter: nil, options: nil, options_src: nil, clear_option: nil)
          raise ArgumentError, "must provide one of: options, options_src" if options.nil? && options_src.nil?
          raise ArgumentError, "may only provide one of: options, options_src" unless options.nil? || options_src.nil?
          super
        end
      end

      sig { params(data: Data, scheme: Symbol, color: Symbol, variant: Symbol).void }
      def initialize(data, scheme: :default, color: :default, variant: :medium)
        @name = T.let(data.name, String)
        @header = T.let(data.header, String)
        @icon = T.let(data.icon, T.nilable(String))
        @filter = T.let(data.filter, T.nilable(Filter))
        @options = T.let(data.options, T.nilable(T::Array[SelectMenu::ListComponent::OptionData]))
        @clear_option = T.let(data.clear_option, T.nilable(ClearOption))
        @scheme = scheme
        @color = color
        @variant = variant

        @menu_id = T.let("security-center-coverage-select-menu-#{SecureRandom.uuid}", String)
        @menu = T.let({}, T::Hash[Symbol, T.untyped])
        options_src = T.let(data.options_src, T.nilable(String))
        if options_src
          # For the filter in the menu to work,
          # it requires the list rendered and returned by 'src' uses the same ID as the menu plus a suffix.
          # So we need to send the menu ID as part of the request payload.
          options_src = append_to_query(options_src, ["menu-id", @menu_id])

          @menu = {
            tag: "details-menu",
            preload: true,
            src: options_src,
          }
        end
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
end
