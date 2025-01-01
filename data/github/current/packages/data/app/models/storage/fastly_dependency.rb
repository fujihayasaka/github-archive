# typed: strict
# frozen_string_literal: true

module Storage::FastlyDependency
  extend T::Helpers

  abstract!

  # Name of the CDN service being used by Fastly
  sig { abstract.returns(T.nilable(String)) }
  def storage_fastly_acceleration_bucket; end

  # The name of the dictionary being used by Fastly for
  # JWT generation
  sig { abstract.returns(T.nilable(String)) }
  def fastly_dictionary_key_name; end

  # The value of the dictionary being used by Fastly for
  # JWT generation
  sig { abstract.returns(T.nilable(String)) }
  def fastly_dictionary_key_value; end

  # The value of the audience being used for JWT generation
  sig { abstract.returns(T.nilable(String)) }
  def fastly_jwt_audience; end

  # The URL to the CDN
  sig { params(url: String).returns(String) }
  def cdn_url(url)
    # We don't use Fastly in Proxima, but the Fastly parsing code below will fail without something configured. As
    # such, let's simply bail out early
    return url if GitHub.multi_tenant_enterprise?

    fastly_bucket = storage_fastly_acceleration_bucket
    return url unless fastly_bucket

    parsed = Addressable::URI.parse(url)
    parsed.host = fastly_bucket
    parsed.to_s
  end

end
