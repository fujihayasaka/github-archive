# frozen_string_literal: true

Diffy::Diff.default_format = :html

Diffy::Diff.default_options.update(
  ignore_crlf: true,
  include_plus_and_minus_in_html: true,
)
