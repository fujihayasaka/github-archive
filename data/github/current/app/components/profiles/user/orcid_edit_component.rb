# typed: strict
# frozen_string_literal: true

module Profiles
  module User
    class OrcidEditComponent < ApplicationComponent
      extend T::Sig
      include ProfilesHelper

      sig { returns(T.untyped) }
      def call
        if orcid_record
          render(Profiles::User::Orcid::DisconnectComponent.new(orcid_record: T.must(orcid_record)))
        else
          render(Profiles::User::Orcid::ConnectComponent.new)
        end
      end

      private

      sig { returns(T::Boolean) }
      def render?
        show_orcid_controls?
      end

      sig { returns(T.nilable(::OrcidRecord)) }
      memoize def orcid_record
        current_user.orcid_record
      end
    end
  end
end
