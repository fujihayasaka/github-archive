# typed: strict
# frozen_string_literal: true

class Stores::StoreAttributes
  sig { returns(::String) }
  def id; end

  sig { returns(::Integer) }
  def spokes_id; end

  sig { returns(::Time) }
  def created_at; end

  sig { returns(T.nilable(::Time)) }
  def deleted_at; end

  sig { returns(::Integer) }
  def owner_id; end

  sig { returns(::Integer) }
  def state; end
end
