# typed: true
# frozen_string_literal: true

module TrustMetadata
  class CreateAttestationForm
    extend T::Sig
    attr_reader :repo, :params

    sig { params(repo: Repository, params: T::Hash[String, T.untyped]).void }
    def initialize(repo, params)
      @repo   = repo
      @params = params
    end

    sig { returns([T.untyped, Set]) }
    def validate_params
      errors = Set.new
      bundle = validate_bundle(errors)

      [bundle, errors]
    end

    sig { params(errors: Set).returns(T.untyped) }
    def validate_bundle(errors)
      bundle = TrustMetadata::SigstoreBundle.new(params["bundle"])
      if bundle.valid?
        bundle
      else
        errors.add("Invalid bundle.")
        nil
      end
    end
  end
end
