# typed: strict
# frozen_string_literal: true

require "serviceowners"

require "gh/dev/sorbet/sigil"

module GH
  module Dev
    module Sorbet
      class FileSigils
        extend T::Helpers

        # Some ruby files are better left untyped. Factories are very DSL heavy and the benefit of
        # typing them is vastly outweighed by the cost. Adding to this list is allowed, but only with
        # very good reason and approval from the team owning this file.
        SKIP_PATHS = T.let(["test/factories"], T::Array[String])

        sig { void }
        def initialize
          @path_sigils = T.let(nil, T.nilable(T::Hash[String, Sigil]))
        end

        sig { returns(T::Hash[String, Sigil]) }
        def path_sigils
          return @path_sigils if @path_sigils

          @path_sigils = {}

          tc_json.fetch("files").each do |file|
            path = file.fetch("path").delete_prefix("./")
            next unless path.end_with?(".rb")

            sigil = file.fetch("sigil", nil)&.downcase || "false"

            @path_sigils[path] = Sigil.deserialize(sigil)
          end

          @path_sigils
        end

        sig { returns(T::Hash[String, Sigil]) }
        def migrateable_path_sigils
          path_sigils.select do |path, _|
            !SKIP_PATHS.any? { |skip| path.start_with?(skip) }
          end
        end

        sig { params(serviceowners: ::Serviceowners::Main).returns(T::Hash[String, T::Hash[Symbol, T::Hash[Symbol, Integer]]]) }
        def service_counts(serviceowners)
          result = {}

          migrateable_path_sigils.each_with_object({}) do |(path, sigil), result|
            spec = serviceowners.spec_for_path(path)
            service = spec&.service&.name

            result[service] ||= { implementation: {}, test: {} }
            type = self.test_file?(path) ? :test : :implementation
            result[service][type][sigil.serialize.to_sym] ||= 0
            result[service][type][sigil.serialize.to_sym] += 1
          end
        end

        private

        sig { returns(T::Hash[String, T::Array[T::Hash[String, String]]]) }
        def tc_json
          out, error, status = Open3.capture3("bundle exec srb tc -p file-table-json")
          raise "Error generating type check output!" if out.empty?
          JSON.parse(out)
        end

        sig { params(path: String).returns(T::Boolean) }
        def test_file?(path)
          path.end_with?("_test.rb")
        end
      end
    end
  end
end
