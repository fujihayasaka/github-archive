# typed: strict
# frozen_string_literal: true

class Closables::Buttons::ReopenComponent < Closables::Buttons::BaseComponent
  extend T::Sig

  private

  sig { returns(T::Boolean) }
  def render?
    closable.closed?
  end

  sig { returns(T::Array[Reason]) }
  memoize def selectable_options
    options - [T.must(current_reason)]
  end

  sig { returns(String) }
  def default_reopen_text
    "Reopen #{closable_name}"
  end

  sig { returns(String) }
  memoize def reopen_icon
    icon = closable.is_a?(Discussion) ? :"comment-discussion" : :"issue-reopened"
    render(Primer::Beta::Octicon.new(
      icon: icon,
      color: :success,
    ))
  end
end
