# typed: strict
# frozen_string_literal: true

# Private: Responsible for orchestrating the encoding of domain objects for the
# purpose of including in a LLM prompt and also decoding and expanding references
# from a completion result.
#
# Examples
#
#   class MyPrompt < Copilot::Prompt::Base
#     # the encoded reference string to use in the prompt
#     def encode_item(user)
#       "@#{user.login}"
#     end
#
#     # the expanded reference string with which to replace
#     # encoded references in the completion result
#     def expand_item(user)
#       template.link_to "@#{user.login}", "/#{user.login}"
#     end
#   end
#
#   # my_prompt_template.text.erb
#   Hi, my name is <%= references.encode(user) %>. Please say hello.
#
#   # Example completion
#   Hi @monalisa, I'm ChatGPT.
#
#   prompt.references.decode_and_expand_all(completion)
#   # => "Hi <a href="/monalisa">@monalisa</a>, I'm ChatGPT."
module Copilot
  module Prompt
    class ReferenceEncoder
      extend T::Sig
      extend T::Generic
      include GitHub::Memoizer

      Item = type_member

      class Reference
        extend T::Sig
        extend T::Generic
        include GitHub::Memoizer

        Item = type_member

        sig { params(encoder: Copilot::Prompt::ReferenceEncoder[Item], item: Item).void }
        def initialize(encoder:, item:)
          @encoder = encoder
          @item = item
        end

        sig { returns(String) }
        memoize def encoded
          @encoder.encode_item(@item)
        end

        sig { returns(Item) }
        def decoded
          @item
        end

        sig { returns(String) }
        memoize def expanded
          @encoder.expand_item(@item)
        end
      end

      sig { returns(Copilot::Prompt::Base[Item]) }
      attr_reader :prompt

      delegate :encode_item, :expand_item, to: :prompt

      sig { params(prompt: Copilot::Prompt::Base[Item]).void }
      def initialize(prompt:)
        @prompt = prompt
      end

      sig { params(item: Item).returns(String) }
      def encode(item)
        T.must(by_item[item]).encoded
      end

      sig { params(encoded: String).returns(T.nilable(Item)) }
      def decode(encoded)
        return unless by_encoded[encoded]

        reference = T.must(by_encoded[encoded])
        reference.decoded
      end

      sig { params(input: String).returns(String) }
      def decode_and_expand_all(input)
        escaped_encodes = by_item
          .values
          .map { |ref| Regexp.escape(ref.encoded) }
          .sort_by { |ref| -ref.length } # sort longest first to avoid incorrect matches
        reference_regexp = Regexp.new(escaped_encodes.join("|"))
        input.gsub(reference_regexp) do |match|
          reference = by_encoded[match]
          next unless reference

          match.replace reference.expanded
        end
      end

      sig { void }
      def clear
        by_item.clear
        by_encoded.clear
      end

      sig { params(item: Item).returns(T::Boolean) }
      def include?(item)
        by_item.key?(item)
      end

      private

      sig { returns(T::Hash[Item, Reference[Item]]) }
      memoize def by_item
        Hash.new do |hash, item|
          hash[item] = Reference[Item].new(encoder: self, item: item)
        end
      end


      sig { returns(T::Hash[String, Reference[Item]]) }
      memoize def by_encoded
        Hash.new do |hash, encoded|
          hash[encoded] = by_item.values.find { |ref| ref.encoded == encoded }
        end
      end
    end
  end
end
