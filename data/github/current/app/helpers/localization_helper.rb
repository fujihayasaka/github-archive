# typed: true
# frozen_string_literal: true

module LocalizationHelper
  # @see Localization._
  def _(key, options = {})
    Localization._(key, options.merge(view_context: true))
  end
end
