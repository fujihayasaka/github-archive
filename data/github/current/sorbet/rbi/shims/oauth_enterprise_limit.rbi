# typed: true

class OauthEnterpriseLimit
  sig { returns(T::Boolean) }
  def higher_limit_eligible; end

  sig { params(value: T::Boolean).returns(T::Boolean) }
  def higher_limit_eligible=(value); end

  sig { returns(Integer) }
  def app_id; end

  sig { params(value: Integer).returns(Integer) }
  def app_id=(value); end

  sig { returns(Integer) }
  def user_id; end

  sig { params(value: Integer).returns(Integer) }
  def user_id=(value); end

  sig { returns(Integer) }
  def request_owner_id; end

  sig { params(value: Integer).returns(Integer) }
  def request_owner_id=(value); end
end
