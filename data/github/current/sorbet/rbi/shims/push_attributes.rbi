# typed: strict
# frozen_string_literal: true

class Repositories::PushAttributes
  sig { returns(T.nilable(::Integer)) }
  def id; end

  sig { returns(T.nilable(::Integer)) }
  def repository_id; end

  sig { returns(T.nilable(::Integer)) }
  def pusher_id; end

  sig { returns(String) }
  def before; end

  sig { returns(String) }
  def after; end

  sig { returns(String) }
  def ref; end

  sig { returns T.nilable(ActiveSupport::TimeWithZone) }
  def created_at; end

  sig { returns(T.nilable(::ActiveSupport::TimeWithZone)) }
  def updated_at
  end

  sig { returns ActiveSupport::TimeWithZone }
  def pushed_at
  end

  sig { returns String }
  def push_type; end
end
