# typed: true
# frozen_string_literal: true

require "digest/sha1"

class DeleteToken
  class DangerZone < StandardError
    attr_reader :token, :attempt
    def initialize(token, attempt)
      @token   = token
      @attempt = attempt
      super "Dangerzoooooone #{token.inspect} #{attempt.inspect}"
    end
  end

  def self.verify!(user, record, attempt)
    token = new user, record
    token.valid?(attempt) || begin
      raise DangerZone.new(token, attempt)
    end
  end

  def self.valid?(user, record, token)
    new(user, record).valid?(token)
  end

  def self.generate(user, record)
    new(user, record).token
  end

  attr_reader :user, :record

  # Simple way to generate and validate per-user tokens for deleting a record.
  # This is a token that should be included in a hidden field on a confirmation
  # form, and then verified before deletion.
  #
  # user   - A user identifying value (such as a DB id, a session id, etc).
  # record - An ActiveRecord model that is being deleted.
  def initialize(user, record)
    @user   = user
    @record = record
    @token  = nil
  end

  def token
    @token ||= begin
      now = Time.now.utc
      Digest::SHA1.hexdigest("%s:%s:%d:%d:%d:%d" % # rubocop:disable GitHub/InsecureHashAlgorithm
        [@user, @record.class, @record.id, now.year, now.month, now.day])
    end
  end

  def valid?(token)
    token == self.token
  end

  def inspect
    %(<DeleteToken %s (%d) %s#%d) %
      [@user.login, @user.id, @record.class, @record.id]
  end
end
