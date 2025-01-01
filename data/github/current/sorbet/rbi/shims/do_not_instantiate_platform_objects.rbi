# typed: true

class RuboCop::Cop::GitHub::DoNotInstantiatePlatformObjects
  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def platform_ip_allowlist_instantiation?(node); end

  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def platform_saml_instantiation?(node); end

  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def conditional_access_enforcer_instantiation?(node); end

  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def conditional_access_filter_instantiation?(node); end
end
