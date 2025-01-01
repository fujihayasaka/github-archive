# typed: true
# frozen_string_literal: true

module Coders
  class NotificationUserSettingCoder < Coders::Base

    data_accessors :emails

    ###
    # Note: Extending inherited to_h to support the field
    # being used to store entire settings data as a pass-through
    def to_h
      data.merge(super)
    end
  end
end
