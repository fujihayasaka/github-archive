# typed: strict
# frozen_string_literal: true

module Profiles
  module User
    module Orcid
      class DisconnectComponent < ApplicationComponent
        extend T::Sig
        include SvgHelper

        sig { params(orcid_record: ::OrcidRecord).void }
        def initialize(orcid_record:)
          @orcid_record = orcid_record
        end

        private

        sig { returns(::OrcidRecord) }
        attr_reader :orcid_record
      end
    end
  end
end
