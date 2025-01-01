# typed: true
# frozen_string_literal: true

class BatchDeferredSponsorButton < T::Struct
  prop :sponsorable_login, T.nilable(String), default: ""
  prop :sponsorable_id, T.nilable(T.any(String, Integer)), default: ""
  prop :location, T.nilable(T.any(String, Symbol)), default: :UNKNOWN
  prop :has_funding_file, T.nilable(T.any(String, T::Boolean)), default: false
  prop :repo_name, T.nilable(T.any(String, Symbol)), default: :UNKNOWN

  sig { returns T::Boolean }
  def has_funding_file?
    has_funding_file.to_s == "true"
  end
end
