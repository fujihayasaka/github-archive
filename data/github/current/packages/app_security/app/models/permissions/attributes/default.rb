# typed: true
# frozen_string_literal: true

require "authzd-client"

module Permissions
  module Attributes
    class Default
      attr_reader :participant

      def initialize(participant)
        @participant = participant
      end

      sig { returns(T.nilable(Integer)) }
      def subject_id
        participant.id
      end

      sig { returns(T.nilable(String)) }
      def subject_type
        participant.try(:user_role_target_type) || participant.class.name
      end

      def subject_attributes
        {
          "subject.type" => subject_type,
          "subject.id"   => subject_id,
        }
      end

      def serialized_subject_attributes
        serialized_attributes(subject_attributes)
      end

      def actor_attributes(actor)
        {}
      end

      def serialized_actor_attributes(actor)
        serialized_attributes(actor_attributes(actor))
      end

      private

      def serialized_attributes(attributes)
        attrs = []
        attributes.each do |key, value|
          Promise.resolve(value).then do |value|
            attrs << Authzd::Proto::Attribute.wrap(key, value)
          end
        end
        attrs
      end
    end
  end
end
