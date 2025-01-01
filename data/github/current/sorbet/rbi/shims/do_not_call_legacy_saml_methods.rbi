# typed: true

class RuboCop::Cop::GitHub::DoNotCallLegacySamlMethods
  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def prohibited_method_call?(node); end
end
