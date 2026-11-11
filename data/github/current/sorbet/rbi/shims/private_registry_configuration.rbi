# typed: true

class PrivateRegistry::Configuration
  sig { returns(T.nilable(String)) }
  def tenant_id; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def tenant_id=(value); end

  sig { returns(T.nilable(String)) }
  def client_id; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def client_id=(value); end

  sig { returns(T.nilable(String)) }
  def aws_region; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def aws_region=(value); end

  sig { returns(T.nilable(String)) }
  def account_id; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def account_id=(value); end

  sig { returns(T.nilable(String)) }
  def role_name; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def role_name=(value); end

  sig { returns(T.nilable(String)) }
  def domain; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def domain=(value); end

  sig { returns(T.nilable(String)) }
  def domain_owner; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def domain_owner=(value); end

  sig { returns(T.nilable(String)) }
  def jfrog_oidc_provider_name; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def jfrog_oidc_provider_name=(value); end

  sig { returns(T.nilable(String)) }
  def audience; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def audience=(value); end

  sig { returns(T.nilable(String)) }
  def identity_mapping_name; end

  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def identity_mapping_name=(value); end
end
