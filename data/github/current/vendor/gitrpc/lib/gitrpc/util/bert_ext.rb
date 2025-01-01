# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "bert"

module BERT
  def self.encode(ruby)
    payload = GitRPC.instrument(:bert_encode) do
      ::BERT::Encoder.encode(ruby)
    end
    GitRPC.instrument(:bert_encode_size, :size => payload.bytesize)

    if payload.bytesize > GitRPC.max_request_size
      raise GitRPC::RequestTooLarge.new(payload.bytesize)
    end
    payload
  end

  def self.decode(bert)
    GitRPC.instrument(:bert_decode_size, :size => bert.bytesize)
    GitRPC.instrument(:bert_decode) do
      ::BERT::Decoder.decode(bert)
    end
  end
end
