# typed: true
# frozen_string_literal: true

module Stafftools
  module AdvancedSecurity
    class MeteredServicesLockFormComponent < ApplicationComponent
      attr_reader :is_bundled, :is_locked, :entity, :disable_padding

      def initialize(is_bundled:, is_locked:, entity:, disable_padding: false)
        @is_bundled = is_bundled
        @is_locked = is_locked
        @entity = entity
        @disable_padding = disable_padding
      end

      def form_method
        is_locked ? :delete : :post
      end

      def button_text
        is_locked ? "Unlock metered services" : "Lock metered services"
      end
    end
  end
end
