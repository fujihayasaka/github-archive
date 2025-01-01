# typed: true
# frozen_string_literal: true

# Delegator to help determine when react is returning a new or an existing reaction
class Reaction
  class RecordStatus < SimpleDelegator
    attr_reader :status

    VALID_STATUSES = [:created, :exists, :invalid, :deleted]

    def initialize(reaction_status)
      reaction, @status = *reaction_status
      Kernel.raise ArgumentError.new("Invalid status: #{@status}") unless VALID_STATUSES.include?(@status)
      super(reaction)
    end

    def created?
      status == :created
    end

    def exists?
      status == :exists
    end

    def platform_type_name
      # This object is a SimpleDelegator to an underlying Reaction
      "Reaction"
    end
  end
end
