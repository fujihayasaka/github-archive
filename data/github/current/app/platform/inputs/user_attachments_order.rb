# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class UserAttachmentsOrder < Platform::Inputs::Base
      description "Ways in which retired user attachments connections can be ordered."
      visibility :internal

      argument :field, Enums::UserAttachmentsOrderField, "The field in which to order nodes by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order nodes.", required: true
    end
  end
end
