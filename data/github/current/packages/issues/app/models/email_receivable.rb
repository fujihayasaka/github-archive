# typed: strict
# frozen_string_literal: true

module EmailReceivable
  extend T::Sig

  sig { returns Symbol }
  def formatter
    fmt = T.unsafe(self).read_attribute(:formatter)
    fmt.blank? ? :markdown : fmt.to_sym
  end

  sig { returns T::Boolean }
  def created_via_email
    formatter == :email
  end
end
