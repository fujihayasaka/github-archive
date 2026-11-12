# frozen_string_literal: true

module GHSAIDGenerator
  extend self

  ID_SPACE = 20**12
  B20_DIGITS = "0123456789abcdefghij"
  OLC_DIGITS = "23456789cfghjmpqrvwx"

  # Generate a GHSA ID in the format of "GHSA-####-####-####" where each "#" is
  # a random, lowercase character. There are 20 possible characters, translated
  # from Base20 to a modified set based on Google's Open Location Code, which
  # allows a set of 20 characters that are optimized to reduce word generation.
  #
  # See: https://github.com/google/open-location-code/blob/master/docs/olc_definition.adoc#open-location-code
  #
  # Example: "GHSA-5qhq-9w8w-49q6"
  def generate_ghsa_id
    SecureRandom.random_number(ID_SPACE)
      .to_s(20)
      .rjust(17, "GHSA-000000000000")
      .tr!(B20_DIGITS, OLC_DIGITS)
      .insert(13, "-")
      .insert(9, "-")
  end

  # Generate a GHSA ID using the same format as .generate, with an additional
  # check for uniqueness across GHSA IDs attached to existing advisories in the
  # database.
  #
  # This method of GHSA ID assignment is technically subject to a race condition
  # if the table isn't locked during assignment and persistence. But the chance
  # of a race condition collision are negligible.
  def generate_unique_ghsa_id
    candidate_ghsa_id = generate_ghsa_id

    # If the GHSA ID already exists, try again. And track the collision,
    # because... what are the odds?! Well I guess they're 1 in
    # 4,096,000,000,000,000.
    if AdvisoryReview.exists?(ghsa_id: candidate_ghsa_id)
      AdvisoryDB.stats.increment("ghsa_id.collision")
      generate_unique_ghsa_id
    else
      candidate_ghsa_id
    end
  end

  # allow specifying the next GHSA ID in test mode
  # some tests need control over which GHSA ID gets assigned
  if Rails.env.test?
    cattr_accessor :next_ghsa_id

    alias orig_generate_ghsa_id generate_ghsa_id

    def generate_ghsa_id
      next_ghsa_id = GHSAIDGenerator.next_ghsa_id

      if next_ghsa_id
        GHSAIDGenerator.next_ghsa_id = nil
        next_ghsa_id
      else
        orig_generate_ghsa_id
      end
    end
  end
end
