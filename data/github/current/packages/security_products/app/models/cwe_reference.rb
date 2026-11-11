# typed: true
# frozen_string_literal: true

class CWEReference < ApplicationRecord::Notify
  belongs_to :source, polymorphic: true, touch: true # TODO make touch a conditional
  belongs_to :cwe, class_name: "CWE"

  # These _FOR_ENTERPRISE constants allow us to enforce that all aspects of an advisory (vuln attributes + associations)
  # missing from enterprise environments have been intentionally excluded (eg. because it's environmentally-dependent
  # like a user id) rather than overlooked.
  ATTRIBUTES_FOR_ENTERPRISE = %w(
    id
    cwe_id
  ).freeze

  ATTRIBUTES_NOT_FOR_ENTERPRISE = [
    "source_type", # the model is built through the Vulnerability association so this gets set automatically
    "source_id", # the model is built through the Vulnerability association so this gets set automatically
  ].freeze

  def self.attributes_for_enterprise
    ATTRIBUTES_FOR_ENTERPRISE
  end
end
