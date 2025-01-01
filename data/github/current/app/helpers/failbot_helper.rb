# typed: true
# frozen_string_literal: true

module FailbotHelper
  def failbot(e, other = {})
    if e.kind_of?(ActionView::TemplateError) && e.respond_to?(:cause)
      # exceptions raised from views are wrapped in TemplateError. This is the
      # most annoying thing ever.
      e = e.cause
    end

    if e.respond_to?(:info) && e.info.is_a?(Hash)
      other = e.info.merge(other || {})
    end

    Failbot.report(e, other)
  end
end
