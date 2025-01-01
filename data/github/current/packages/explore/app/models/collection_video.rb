# typed: true
# frozen_string_literal: true

class CollectionVideo < ApplicationRecord::Ballast
  extend GitHub::Encoding
  force_utf8_encoding :description
end
