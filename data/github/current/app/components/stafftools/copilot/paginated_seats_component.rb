# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::PaginatedSeatsComponent < ApplicationComponent

  sig { returns(ActiveRecord::Relation) }
  attr_reader :copilot_seats

  sig { returns(T.any(::Organization, ::Business)) }
  attr_reader :entity

  sig { params(copilot_seats: ActiveRecord::Relation, entity: T.any(::Organization, ::Business)).void }
  def initialize(copilot_seats, entity)
    @copilot_seats        = copilot_seats
    @entity               = entity
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
