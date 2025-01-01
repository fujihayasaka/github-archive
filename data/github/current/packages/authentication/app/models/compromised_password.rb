# typed: true
# frozen_string_literal: true

class CompromisedPassword < ApplicationRecord::Collab
  def readonly?
    !new_record?
  end

  # The key which is used through the app to store information about the status of
  # the password being compromised (i.e. should the weak password banner be displayed)
  WEAK_PASSWORD_KEY = :user_password_is_weak

  # We match on hex digits. We can't match on a partial hex digit.
  # No matter what we pick for an upper bound for matches, it is going to be rare
  # that an integral number of hex digits will exactly match the desired number
  # of results. We want to target the number of matches such that we neither have
  # too many nor too few on average. And, we want this to be true in cases where
  # we end up rounding up to the next nearest hex digit. By targeting 2**9 = 512
  # matches, we also ensure that even in the worse case scenario, where we end up
  # rounding up nearly a full hex digit, we will still return matches. Even with
  # 16X fewer matches we end up with non-zero matches on average (512 / 16 = 32).
  MAXIMUM_MATCHES = 2**9

  # Our math for calculating how many hex digits we should query on relies on doing
  # a logarithm calculation that will not work unless the number of records we have
  # is at least twice as large as our minimum number of matches
  MINIMUM_RECORD_COUNT = MAXIMUM_MATCHES * 2

  validates_length_of :sha1_password, is: 40

  # Public: Each hex digit we do a fuzzy match off of decreases the number of matching
  # records by 16X. We need to compute how many digits to use such that the number
  # of records we return is a suitably sized maximum number of records. While
  # somewhat arbitrary, we decided that 2^9 (512) was the most appropriate upper
  # bound. This value was chosen because we must increment the number of digits
  # we use in whole digits (i.e. we can't use a half a hex digit). As a result,
  # in some cases we could end up rounding by nearly an entire whole hex digit,
  # and thus decreasing the returned records by 16X more than would be ideal.
  # By targetting 512 records we ensure that, in the worst case, our rounding
  # results in 512 / 16 = 32 records.
  #
  # DatabaseSize    9
  # ------------ < 2
  #        x
  #      16
  #
  # Rearrange the equation such that we can solve for x
  #
  # DatabaseSize     x
  # ------------ < 16
  #       9
  #      2
  #
  # Take the base16 log of both sides
  #
  #      /DatabaseSize\
  # log  |------------| < x
  #    16|      9     |
  #      \     2      /
  #
  #
  # Since we want x to be "greater than what is on the left" we can take the
  # ceiling of the left side to get what we want. Translated to Ruby we end up
  # with:
  #
  # Math.log(DatbaseSize/(2**9), 16).ceil
  #
  # Example
  #
  # Math.log(1500000000/(2**9), 16).ceil
  # # => 6
  #
  # Returns the number of max digit that is larger than 1 but less than 512
  def self.prefix_to_match
    @hex_digits_to_match ||= begin
      record_count = CompromisedPassword.maximum(:id).to_i
      # In order for the calculation to work we require at least MAXIMUM_RECORD_COUNT
      # records. This is always true in production, but can be less in tests and such.
      record_count = MINIMUM_RECORD_COUNT unless record_count > MINIMUM_RECORD_COUNT
      0...Math.log(record_count / MAXIMUM_MATCHES, 16).ceil
    end
  end

  # Checks, using K Anonimity, if the user's password was contained in the
  # compromised_passwords table. If a match is found we return the datasource
  # bitmask, otherwise we return 0 for no match
  def self.find_using_password(password, user: nil, action: "unknown", role: :reading, correct_password: true, stat: true)
    return unless GitHub.weak_password_checking_enabled?
    # The compromised passwords DB stores hashes in upper case so whe checking
    # if a hash matches we must ensure the hash is also upper case
    password_hash = Digest::SHA1.hexdigest(password).upcase # rubocop:disable GitHub/InsecureHashAlgorithm

    # This should always perform as a read but we do offer the ability to read from master
    # in the unique case when we insert a bunch of data into the db and need to load the
    # compromised password right away (qintel import)
    ActiveRecord::Base.connected_to(role: role, prevent_writes: true) do
      prefix = password_hash[prefix_to_match]

      compromised_password = with_prefix(:sha1_password, prefix).find do |record|
        record[:sha1_password].upcase == password_hash
      end

      if stat
        instrument_compromised_password(
          found: compromised_password,
          user: user,
          action: action,
          correct_password: correct_password,
        )
      end

      compromised_password
    end
  end

  def self.instrument_compromised_password(found:, user:, action:, correct_password:)
    if action
      block_type = if user
        if user.password_check_metadata.exact_match?
          "exact_match"
        elsif user.password_check_metadata.weak_password_past_expiration?
          "30_days"
        else
          false
        end
      end

      tags = [
        "compromised:#{!!found}",
        "action:#{action}",
        "employee:#{user&.employee?}",
        "spammy:#{user&.spammy?}",
        "tfa_enabled:#{user&.two_factor_authentication_enabled?}",
        "correct_password:#{correct_password}",
        "valid_user:#{!!user}",
        "block_type:#{block_type}",
      ]
      GitHub.dogstats.increment("auth.compromised_password", tags: tags)
    end
  end
end
