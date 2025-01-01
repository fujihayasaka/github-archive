# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class StandaloneFormComponent < ApplicationComponent
      extend T::Sig
      renders_one :form_content

      sig { params(copilot_business: Copilot::Business).void }
      def initialize(copilot_business)
        @copilot_business = T.let(copilot_business, Copilot::Business)
      end

      sig { returns(Integer) }
      def org_count
        @copilot_business.copilot_enabled_organizations_count
      end

      sig { returns(Integer) }
      def member_count
        @copilot_business.copilot_enabled_members_count
      end

      sig { returns(T::Boolean) }
      def render?
        @copilot_business.copilot_standalone?
      end
    end
  end
end
