# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    module Metadata
      class BaseComponent < ApplicationComponent
        extend T::Helpers

        abstract!

        sig { params(metadata_record: EducationDeveloperPackApplicationMetadata).void }
        def initialize(metadata_record:)
          @metadata_record = metadata_record
        end

        sig { returns(T.nilable(String)) }
        def call
          render(Primer::Beta::BorderBox.new(padding: :default, mx: 4, mb: 4, mt: 2)) do |component|
            component.with_header(bg: header_background_scheme).with_content(header_content)
            component.with_body.with_content(body_content)
          end
        end

        private

        sig { returns(EducationDeveloperPackApplicationMetadata) }
        attr_reader :metadata_record

        sig { abstract.returns(Symbol) }
        def header_background_scheme; end

        sig { abstract.returns(T.nilable(String)) }
        def header_content; end

        sig { abstract.returns(T.nilable(String)) }
        def body_content; end
      end
    end
  end
end
