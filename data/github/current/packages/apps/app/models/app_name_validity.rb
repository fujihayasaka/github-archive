# typed: true
# frozen_string_literal: true

module AppNameValidity
  extend T::Helpers

  AppTypes = T.type_alias { T.any(Integration, OauthApplication) }

  # Public: Returns true if this object's `name` starts with GitHub or Gist, case insensitive.
  def name_starts_with_github?
    T.bind(self, AppTypes)
    normalized_name = T.must(name).downcase.gsub(/\s+/, "")
    starts_with_github?(normalized_name)
  end

  # Public: Returns true if this object's `name` implies the object is a GitHub product.
  def name_implies_github_affiliation?
    T.bind(self, AppTypes)
    normalized_name = T.must(name).downcase.gsub(/\s+/, "")
    implies_github_affiliation?(normalized_name)
  end

  def name_includes_urls?
    T.bind(self, AppTypes)
    normalized_name = T.must(name).downcase.gsub(/\s+/, "")
    URI.extract(normalized_name, %w(http https)).any?
  end

  def name_parameterizes_to_start_with_github?
    T.bind(self, AppTypes)
    normalized_slug = T.must(name).parameterize.downcase
    starts_with_github?(normalized_slug)
  end

  def name_parameterizes_to_imply_github_affiliation?
    T.bind(self, AppTypes)
    normalized_slug = T.must(name).parameterize.downcase
    implies_github_affiliation?(normalized_slug)
  end

  private

  def starts_with_github?(string)
    /\A(?:github|gist).*\z/.match?(string)
  end

  def implies_github_affiliation?(string)
    /\A.*(?:from|by)(-| |)github\z/.match?(string)
  end
end
