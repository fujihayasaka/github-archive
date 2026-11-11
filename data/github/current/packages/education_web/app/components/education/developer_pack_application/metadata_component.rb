# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class MetadataComponent < ApplicationComponent
      METADATA_STATUS_COMPONENT_MAPPING = T.let(
        {
          coupon_applied: Metadata::ApprovedComponent,
          approved: Metadata::ApprovedComponent,
          denied: Metadata::DeniedComponent,
          expired: Metadata::ExpiredComponent,
          pending: Metadata::PendingComponent,
        }.freeze,
        T::Hash[
          Symbol,
          T.any(
            T.class_of(Metadata::ApprovedComponent),
            T.class_of(Metadata::DeniedComponent),
            T.class_of(Metadata::ExpiredComponent),
            T.class_of(Metadata::PendingComponent),
          ),
        ],
      )

      sig { params(metadata_record: EducationDeveloperPackApplicationMetadata).void }
      def initialize(metadata_record:)
        @metadata_record = metadata_record
      end

      sig { returns(T.nilable(String)) }
      def call
        component = METADATA_STATUS_COMPONENT_MAPPING[metadata_record.status]
        return unless component

        render(Primer::Box.new(test_selector: "metadata-#{metadata_record.id}")) do
          render component.new(metadata_record:)
        end
      end

      private

      sig { returns(EducationDeveloperPackApplicationMetadata) }
      attr_reader :metadata_record
    end
  end
end
