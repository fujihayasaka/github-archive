# typed: strict
# frozen_string_literal: true

module Tapioca
  module Compilers
    class TwirpClient < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(::Twirp::Client) } }

      sig { override.returns(T::Enumerable[T.class_of(::Twirp::Client)]) }
      def self.gather_constants
        ::Twirp::Client.subclasses
      end

      sig { override.void }
      def decorate
        root.create_class(constant.to_s, superclass_name: "::Twirp::Client") do |klass|
          klass.create_method(
            "initialize",
            return_type: "void",
            parameters: [
              create_param("connection", type: "T.any(String, ::Faraday::Connection)"),
              create_opt_param("opts", type: "T::Hash[Symbol, T.untyped]", default: "{}"),
            ]
          )

          constant.rpcs.each do |_, rpc_config|
            klass.create_method(
              rpc_config[:ruby_method],
              return_type: "::Twirp::ClientResp[#{rpc_config[:output_class]}]",
              parameters: [
                create_param("input", type: rpc_config[:input_class].to_s),
                create_opt_param("req_opts", type: "T.nilable(T::Hash[Symbol, T.untyped])", default: "nil")
              ],
            )
          end
        end
      end
    end
  end
end
