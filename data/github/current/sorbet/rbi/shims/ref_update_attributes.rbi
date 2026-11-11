# typed: strict
# frozen_string_literal: true

class Repositories::RefUpdateAttributes
  sig { returns(T.nilable(::Integer)) }
  def id; end

  sig { returns(T.nilable(::Integer)) }
  def push_id; end

  sig { returns(T.nilable(::Integer)) }
  def repository_id; end

  sig { returns(String) }
  def before_oid; end

  sig { returns(String) }
  def after_oid; end

  sig { returns(String) }
  def ref; end

  sig { returns T.nilable(String) }
  def ref_update_type; end
end
