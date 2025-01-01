# typed: true
# frozen_string_literal: true

module TemplatableContent
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  abstract!

  METADATA_KEY = "template_metadata".freeze
  TEMPLATE_PATH_KEY = "__template_path".freeze
  TEMPLATE_PATH_REGEX = /<!--\s#{METADATA_KEY}\s=\s\{.+"#{TEMPLATE_PATH_KEY}":"(.+\.yml)".+-->/

  def template_metadata
    template_path_regex = /<!--\s#{METADATA_KEY}\s=\s(.+)\s-->/
    matches = body.match(template_path_regex)
    matches && JSON.parse(T.must(matches[1]))
  end

  def template_path_from_comment_metadata
    matches = body.match(TEMPLATE_PATH_REGEX)
    matches && matches[1]
  end

  sig { abstract.returns(String) }
  def body; end
end
