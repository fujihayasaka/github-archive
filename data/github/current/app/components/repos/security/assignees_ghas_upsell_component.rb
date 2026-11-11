# typed: strict
# frozen_string_literal: true

class Repos::Security::AssigneesGhasUpsellComponent < ApplicationComponent
  GHAS_DOC_PATH = T.let(
    "/get-started/learning-about-github/about-github-advanced-security#github-code-security",
    String,
  )

  sig do
    params(
      alert_type_label: String,
      learn_more_url: String,
    ).void
  end
  def initialize(alert_type_label:, learn_more_url:)
    @alert_type_label = alert_type_label
    @learn_more_url = learn_more_url
  end

  sig { returns(String) }
  def ghas_doc_url
    "#{GitHub.help_url}#{GHAS_DOC_PATH}"
  end

  sig { returns(String) }
  attr_reader :alert_type_label

  sig { returns(String) }
  attr_reader :learn_more_url
end
