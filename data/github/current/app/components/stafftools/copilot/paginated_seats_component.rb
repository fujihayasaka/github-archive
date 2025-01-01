# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::PaginatedSeatsComponent < ApplicationComponent

  sig { returns(ActiveRecord::Relation) }
  attr_reader :copilot_seats

  sig { returns(T::Boolean) }
  attr_reader :can_be_canceled

  sig { params(copilot_seats: ActiveRecord::Relation).void }
  def initialize(copilot_seats)
    @copilot_seats        = copilot_seats
    @can_be_canceled      = T.let(true, T::Boolean)
    # if any of the copilot_seats are EnterpriseTeam, they can't be canceled
    @can_be_canceled      = @copilot_seats.select { |seat| seat.symbolized_assignable_type == :ENTERPRISE_TEAM }.empty?
  end

  sig { returns(T::Hash[Integer, Copilot::AdministrativeBlock]) }
  memoize def administrative_blocks
    Copilot::AdministrativeBlock.where(blockable: @copilot_seats.map(&:assigned_user_id)).order("created_at DESC").inject(Hash.new) do |acc, block|
      acc[block.blockable_id] = [] unless acc.key?(block.blockable_id)
      acc[block.blockable_id] << block
      acc
    end
  end
end
