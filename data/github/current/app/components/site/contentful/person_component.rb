# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    class PersonComponent < ApplicationComponent
      def initialize(person:)
        @person = person
      end

      def render?
        @person.present?
      end

      def fullname
        "#{@person.first_name} #{@person.last_name}".strip
      end
    end
  end
end
