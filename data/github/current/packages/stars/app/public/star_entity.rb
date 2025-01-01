# typed: strict
# frozen_string_literal: true

StarEntity = Data.define(
  :id,
  :user_id,
  :starrable_id,
  :starrable_type,
  :user_hidden,
  :created_at
)
