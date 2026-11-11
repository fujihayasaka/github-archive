# typed: true
# frozen_string_literal: true

# The model object that represents when a user was whitelisted and why.
#
# This class is an untested implementation detail, since we didn't want
# to add these fields to every user in the database. See
# user/rate_limit_whitelisting_dependency.rb for the public interface to using
# this class.
class UserWhitelisting < ApplicationRecord::Domain::Users
  belongs_to :user
  belongs_to :whitelister, class_name: "User"
end
