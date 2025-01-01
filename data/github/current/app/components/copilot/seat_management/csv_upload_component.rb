# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class CsvUploadComponent < ApplicationComponent
      extend T::Sig

      sig { params(organization: ::Organization, parsed_csv: T.nilable(T::Hash[String, T::Array[T::Hash[String, T.any(::User, String, T::Boolean)]]]), error: T.nilable(OrganizationInvitation::InvalidError)).void }
      def initialize(organization, parsed_csv = nil, error = nil)
        @organization = organization
        @error = error
        @parsed_csv = parsed_csv
      end
    end
  end
end
