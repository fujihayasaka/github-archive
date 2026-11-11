# typed: false
# frozen_string_literal: true

# A SequenceContext defines a unique scope that can be used with the Sequence class.
# Anything that returns the same (sequence_context_type, sequence_context_id) pair
# will generate numbers from the same sequence.
#
# Examples:
#
#   To generate a sequence in the scope of a Repository:
#
#   class Entity1:
#       def sequence_context_type
#         repository.class.name
#       end
#
#      def sequence_context_id
#        repository.id
#      end
#
#      def set_number
#        Sequence.create(self) unless Sequence.exists?(self)
#        self.number ||= Sequence.next(self)
#       end
#   end
#
#   To share a single sequence for two different entities belonging to a Repository:
#
#   Use the same implementation as above for `sequence_context_type` and `sequence_context_id` in the other entities that
#   require to share the same sequence.
#
#   To generate two different sequences for two entities belonging to the same Repository:
#
#   This will create two independent sequences for the top level repository:
#   1. Sequence for numbering entity 1: ("entity1", repository-id)
#   2. Sequence for numbering entity 2: ("entity2", repository-id)
#
#   class Entity1:
#       def sequence_context_type
#         self.class.name
#       end
#
#      def sequence_context_id
#        repository.id
#      end
#
#      def set_number
#        Sequence.create(self) unless Sequence.exists?(self)
#        self.number ||= Sequence.next(self)
#       end
#   end
#
#   class Entity2:
#       def sequence_context_type
#         self.class.name
#       end
#
#      def sequence_context_id
#        repository.id
#      end
#
#      def set_number
#        Sequence.create(self) unless Sequence.exists?(self)
#        self.number ||= Sequence.next(self)
#       end
#   end
module Sequence::Context
  extend ActiveSupport::Concern

  def sequence_context_type
    raise NotImplementedError
  end

  def sequence_context_id
    raise NotImplementedError
  end
end
