# typed: strict
# frozen_string_literal: true

module Organizations
  module Settings
    class RecommendedMemexProjectsDialogComponent < ApplicationComponent
      extend T::Sig

      sig { returns(Organization) }
      attr_reader :organization

      sig { params(organization: Organization).void }
      def initialize(organization:)
        @organization = organization
      end
    end
  end
end
