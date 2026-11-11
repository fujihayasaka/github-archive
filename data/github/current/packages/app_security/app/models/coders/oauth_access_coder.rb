# typed: true
# frozen_string_literal: true

module Coders
  class OauthAccessCoder < Coders::Base
    data_accessors \
      :note,
      :note_url,
      :requested_scopes,
      :scopes,
      :requested_redirect_uri

    # track changes to the scopes property other props can be added to
    # the defined_attribute_methods definition when needed
    include ActiveModel::Dirty
    define_attribute_methods :scopes

    # changing the scopes will allow the #changed? and the
    # scopes_changed? method evaluate to true
    def scopes=(new_value)
      return if new_value == data[:scopes] # nothing changes

      attribute_will_change!("scopes")
      data[:scopes] = new_value
    end
  end
end
