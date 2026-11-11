# typed: true
# frozen_string_literal: true

ActiveSupport.on_load(:action_view) do
  ActionView::Base.field_error_proc = proc do |html_tag, _instance|
    "<div class=\"field-with-errors\">#{html_tag}</div>".html_safe # rubocop:disable Rails/OutputSafety
  end
end
