# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Beta
    class Participant
      extend T::Sig

      sig { params(user: User).returns(Participant) }
      def self.from_user(user)
        new(randomization_id: user.id.to_s, type: Type::User, staff: user.metadata.is_staff?)
      end

      sig { params(visitor: Analytics::Visitor, staff_override: T::Boolean).returns(Participant) }
      def self.from_visitor(visitor, staff_override: false)
        new(randomization_id: visitor.unversioned_octolytics_id, type: Type::Visitor, staff: staff_override)
      end

      sig { returns(String) }
      attr_reader :randomization_id

      sig { returns(Type) }
      attr_reader :type

      sig { params(randomization_id: String, type: Type, staff: T::Boolean).void }
      def initialize(randomization_id:, type:, staff: false)
        @randomization_id = T.let(randomization_id, String)
        @type = T.let(type, Type)
        @staff = T.let(staff, T::Boolean)
      end

      sig { returns(T::Boolean) }
      def staff?
        @staff
      end

      sig { returns(T::Array[Namespace]) }
      def namespaces
        AssignmentService.assignment(self)
      end

      class Type < T::Enum
        extend T::Sig

        enums do
          User         = new
          Visitor      = new
          Organization = new
          Repository   = new
        end

        sig { returns(Symbol) }
        def to_sym
          case self
          # User and Visitor are combined as "ACTOR" for now until we can update the Hydro event
          when User, Visitor then :ACTOR
          when Organization  then :ORGANIZATION
          when Repository    then :REPOSITORY
          else
            T.absurd(self)
          end
        end
      end
    end
  end
end
