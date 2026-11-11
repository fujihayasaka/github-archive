# typed: true
# frozen_string_literal: true

class CollectionUrl < ApplicationRecord::Ballast
  extend GitHub::Encoding
  force_utf8_encoding :description
end
