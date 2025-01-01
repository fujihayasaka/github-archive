# typed: false
# frozen_string_literal: true

module Repository::DeployKeysDependency
  # Deploy Keys
  def public_keys=(new_keys)
    new_keys = [new_keys].flatten.reject(&:blank?)

    public_keys.each do |key|
      public_keys.delete(key) unless new_keys.include? key.to_s
      new_keys.delete(key.to_s)
    end

    new_keys.each do |key|
      pk = PublicKey.new(repository: self, key: key.to_s)
      public_keys << pk
    end
  end

  def unverified_public_keys?
    public_keys.any? { |key| !key.verified? }
  end
end
