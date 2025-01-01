# typed: strict
# frozen_string_literal: true

module BlackbirdSearch
  class Experiments
    # Setting blackbird experiments for a repo alters indexing behavior.
    #   - blackbird_enable_code_embedding: blackbird will compute and index embeddings for code and markdown in the
    #     repo.
    sig do
      params(
        cir: T.nilable(CopilotIndexedRepositories)
      ).returns(T::Hash[String, String])
    end
    def self.get(cir)
      return {} unless cir.present?

      experiments = {}
      experiments["blackbird_enable_code_embedding"] = "1"
      experiments
    end
  end
end
