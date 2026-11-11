# frozen_string_literal: true

require "base62"
require "rbnacl"
require "github_helpers"

class GenerateJobCredTokens
  # The main method that generates both the external job token and external cred token
  # Returns a hash containing the generated tokens
  def run
    {
      external_job_token: generate_job_token,
      external_cred_token: generate_cred_token,
    }
  end

  # Generates the external job token by creating a token string and adding a 6-digit
  # checksum for validation purposes
  # Returns a hash containing the job token and its hashed representation
  def generate_job_token
    token = generate_token
    hashed_token = get_hashed_token(token)
    base64_job_token = token_base64_encoding(token)
    # In accordance with the recommendation from secret scanning, a 32 bit checksum in the
    # last 6 digits of each token is being added to the token for improved validation.
    job_token = UpdateJob::DEPENDABOT_JOB_TOKEN_PREFIX + base64_job_token + checksum(base64_job_token)
    { job_token: job_token, hashed_token: hashed_token }
  end

  # Generates the external cred token by creating a token string and adding a 6-digit
  # checksum for validation purposes
  # Returns a hash containing the cred token and its hashed representation
  def generate_cred_token
    token = generate_token
    hashed_token = get_hashed_token(token)
    base64_cred_token = token_base64_encoding(token)
    cred_token = UpdateJob::DEPENDABOT_CRED_TOKEN_PREFIX + base64_cred_token + checksum(base64_cred_token)
    { cred_token: cred_token, hashed_token: hashed_token }
  end

  def generate_autofix_token
    token = generate_token
    hashed_token = get_hashed_token(token)
    base64_pr_token = token_base64_encoding(token)
    pr_token = PullRequest::DEPENDABOT_PR_TOKEN_PREFIX + base64_pr_token + checksum(base64_pr_token)
    { pr_token: pr_token, hashed_token: hashed_token }
  end

  private

  def token_base64_encoding(token)
    Base64.strict_encode64(token)
  end

  def get_hashed_token(token)
    Base64.strict_encode64(RbNaCl::Hash.sha256(token))
  end

  def generate_token
    RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes)
  end

  # Computes a 6-digit checksum for the given token using the Zlib and Base62 libraries
  # Returns the computed checksum as a string
  def checksum(token)
    crc_value = Zlib.crc32(token)
    base62_str = Base62.encode(crc_value)
    base62_str.rjust(6, Base62::PRIMITIVES[0])
  end
end
