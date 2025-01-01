# frozen_string_literal: true

class AiPrediction < ApplicationRecord
  include AASM
  MAX_PROMPT_CHAR = 8000

  belongs_to :advisory_review

  enum :curator_decision, {
    pending: 0,
    rejected: 1,
    accepted: 2,
  }

  aasm column: :curator_decision, enum: true, whiny_persistence: true do
    state :pending, initial: true
    state :rejected
    state :accepted

    after_all_transitions :update_decided_at

    event :reject do
      transitions from: :pending, to: :rejected
    end

    event :accept do
      transitions from: :pending, to: :accepted
    end
  end

  def update_decided_at
    self.decided_at = Time.zone.now
  end

  # TODO: (maybe) add this as a new column in ai_prediction table
  def prediction_context
    "You are a security analyst that specializes in security advisories."
  end

  def supported_ecosystems
    AdvisoryDB::Config::Ecosystems::PROMPT_ECOSYSTEMS.map { |e| AdvisoryDB.ecosystem_label(e) }
  end

  # TODO: (maybe) add this as a new column in ai_prediction table
  def prompt
    package_formats = supported_ecosystems.map { |e| "-#{e}: #{AdvisoryDB::Config::Ecosystems::PROMPT_PACKAGE_FORMAT_EXAMPLES.fetch(e)}" }
    self.summary = advisory_review.summary || ""
    # truncate so that summary + description length together do not exceed MAX_PROMPT_CHAR
    self.description = advisory_review.description&.truncate(MAX_PROMPT_CHAR - summary.length, omission: "")

    self.prompt = "The following is a security advisory:
    ---
    #{summary}

    #{description}
    ---
    Select the ecosystem and full package name for this advisory.
    Classify the advisory into one of the following ecosystems: #{supported_ecosystems.join(", ")}.
    The ecosystem name *must* be one of the ecosystems listed above. Even if you think none of these is the correct answer, you must select the most likely option.
    The package name should be in the format used to install the package. The format differs by ecosystem. Be sure to use the correct format for the selected ecosystem. Here are some examples:
    #{package_formats.join("\n")}
    If there is more than one package name, return a comma-separated list of package names sorted alphabetically. For example, if the advisory affects the packages 'foo' and 'bar', return 'bar, foo'.
    Return your response in the following format:
    Ecosystem: <fill in the ecosystem>
    Package name: <fill in the full package name>"
  end

  def messages
    [
      {
        role: "system",
        content: prediction_context,
      },
      {
        role: "user",
        content: prompt,
      },
    ]
  end

  def process_ecosystem_prediction(raw_predicted_ecosystems)
    self.predicted_ecosystems = if supported_ecosystems.include?(raw_predicted_ecosystems)
                                  # we want to store the ecosystem in the format consistant with
                                  # the advisory_review table e.g. "maven" instead of "Maven"
                                  AdvisoryDB.ai_prediction_result_to_ecosystem(raw_predicted_ecosystems)
                                else
                                  "other"
                                end
  end

  def process_package_prediction(raw_predicted_ecosystems, raw_predicted_packages)
    self.predicted_packages = if raw_predicted_packages.nil?
                                ""
                              else
                                case raw_predicted_ecosystems
                                when "GitHub Actions", "Composer", "Go"
                                  raw_predicted_packages.match?(%r{\w+/\w+}) ? raw_predicted_packages : ""
                                when "Erlang", "pip", "npm", "Pub.dev", "RubyGems"
                                  raw_predicted_packages.match?(/\w+/) ? raw_predicted_packages : ""
                                when "Maven"
                                  raw_predicted_packages.match?(/\w+.\w+.\w+:\w+/) ? raw_predicted_packages : ""
                                when "Rust"
                                  raw_predicted_packages.match?(/\A[a-zA-Z0-9\-_]+\z/) ? raw_predicted_packages : ""
                                else
                                  raw_predicted_packages
                                end
                              end
  end
end
