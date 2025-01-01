# typed: true
# frozen_string_literal: true

class SpamDatasource < ApplicationRecord::Domain::Spam
  include GitHub::Validations
  has_many :entries,
    -> { order("id ASC") },
    class_name: "SpamDatasourceEntry"

  # Datasource names will be in the form of a slug aka
  # new_user_triage, possible_spammers, etc
  validates_presence_of :name
  validates_uniqueness_of :name, case_sensitive: false
  validates :name, unicode3: true
  validates :description, unicode3: true

  # Public: Sets the new name
  #
  # This takes the new name given and converts it
  # into the form we want.  For example:
  # "Allowed Address List" => "allowed_address_list"
  def name=(new_name)
    new_name = new_name.to_s.downcase
    new_name.gsub! " ", "_"
    super new_name
  end

  # Public: Human friendly version of name
  # allowed_address_list -> Allowed Address List
  def human_name
    name.to_s.split("_").map { |word| word.capitalize }.join " "
  end
end
