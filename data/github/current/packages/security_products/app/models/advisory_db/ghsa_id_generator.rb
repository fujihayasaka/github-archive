# typed: true
# frozen_string_literal: true

module AdvisoryDB
  module GhsaIdGenerator
    extend self

    ID_SPACE = 20**12
    B20_DIGITS = "0123456789abcdefghij"
    OLC_DIGITS = "23456789cfghjmpqrvwx"

    # Generate a GHSA ID in the format of "GHSA-####-####-####" where each "#" is
    # a random, lowercase character. There are 20 possible characters, translated
    # from Base20 to a modified set based on Google's Open Location Code, which
    # allowlists a set of 20 characters that are optimized to reduce word
    # generation.
    #
    # See: https://github.com/google/open-location-code/blob/master/docs/olc_definition.adoc#open-location-code
    #
    # Example: "GHSA-5qhq-9w8w-49q6"
    def generate_ghsa_id
      T.must(SecureRandom.random_number(T.cast(ID_SPACE, Integer)).
        to_s(20).
        rjust(17, "GHSA-000000000000").
        tr!(B20_DIGITS, OLC_DIGITS)).
        insert(13, "-").
        insert(9, "-")
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
      # because… what are the odds‽ Well I guess they're 1 in
      # 4,096,000,000,000,000.
      if ghsa_id_exists?(candidate_ghsa_id)
        GitHub.dogstats.increment("ghsa_id.collision")
        generate_unique_ghsa_id
      else
        candidate_ghsa_id
      end
    end

    # Check to see if a given GHSA ID exists across all models
    def ghsa_id_exists?(ghsa_id)
      Vulnerability.where(ghsa_id: ghsa_id).exists? ||
        RepositoryAdvisory.where(ghsa_id: ghsa_id).exists?
    end
  end
end
