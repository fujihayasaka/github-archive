# typed: strict
# frozen_string_literal: true

module VariantAnalysis::SignedAuthToken
  # Scope for a signed auth token valid for updating a repo task owned by the given variant analysis.
  # This token is used by the CodeQL variant analysis action.
  sig { params(controller_repo_id: Integer, variant_analysis_id: Integer).returns(String) }
  def self.update_scope(controller_repo_id, variant_analysis_id)
    "CodeqlVariantAnalysis/update/#{controller_repo_id}/#{variant_analysis_id}"
  end

  # Create a signed auth token with an update scope
  sig { params(variant_analysis: CodeqlVariantAnalysis).returns(String) }
  def self.create_update_token(variant_analysis)
    T.must(variant_analysis.actor).signed_auth_token({
      scope: VariantAnalysis::SignedAuthToken.update_scope(variant_analysis.controller_repo_id, variant_analysis.id),
      expires: 1.day.from_now
    })
  end
end
