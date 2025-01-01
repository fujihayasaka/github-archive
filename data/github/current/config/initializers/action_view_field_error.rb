# typed: true
# frozen_string_literal: true

ActionView::Base.field_error_proc = proc do |html_tag, _instance|
  "<div class=\"field-with-errors\">#{html_tag}</div>".html_safe # rubocop:disable Rails/OutputSafety
end
