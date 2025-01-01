# frozen_string_literal: true

class NilClass
  def can?(action, subject)
    subject.permit? self, action
  end

  def permit?(*)
    false
  end

  def async_permit?(*)
    Promise.resolve(false)
  end

  def ability_delegate
    self
  end
end
