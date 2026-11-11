# typed: true

class RuboCop::Cop::GitHub::DoNotReferenceFGPModel
  sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
  def fgp_model?(node); end
end
